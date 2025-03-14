package smtp_utils2;

use strict;
use warnings;

use threads;
use Socket;
use Cwd;
use IO::Epoll;
use Net::DNS qw(mx);
use Digest::SHA qw(sha1);
use Digest::HMAC;
use Net::SMTP::SSL;
use Authen::SASL;
use MIME::Base64;

my $max_conn = 5;
my $smtp_server;

my $aioPerlDomain = "aioperl.de";

$smtp::epoll = epoll_create(1024) or die "Failed to create epoll: $!";

my $secret_key = no_upload::get_srs_secret_key();
sub start_smtp_server {
    my $server_thread = threads->create(\&run_smtp_server);
    $server_thread->detach();
}

sub run_smtp_server {
    setup_smtp_server();
    print("Running SMTP server\n");
    epoll_loop();
}

sub setup_smtp_server {
    print("Setting up SMTP server\n");

    print("Starting SMTP server\n");
    socket($smtp_server, AF_INET, SOCK_STREAM, 0);

    print("Setting socket options\n");
    setsockopt($smtp_server, SOL_SOCKET, SO_REUSEADDR, 1) || die "Can't set socket options: $!";
    
    print("Binding to port 25\n");
    bind($smtp_server, sockaddr_in(25, INADDR_ANY)) || die "Can't bind to port 25: $!";

    print("Listening on port 25\n");
    listen($smtp_server, $max_conn) || die "Can't listen: $!";

    epoll_ctl($smtp::epoll, EPOLL_CTL_ADD, fileno $smtp_server, EPOLLIN) >= 0 or die "Failed to add server to epoll: $!";
}

sub epoll_loop {
    print("Starting epoll loop\n");
    while (1) {
        my $events = epoll_wait($smtp::epoll, 10, -1);
        # print("Waiting for SMTP events\n");

        for my $event (@$events) {
            my $fd = $event->[0];
            if ($fd == fileno $smtp_server) {
                accept_client();
                # print("Added client to epoll\n");
            } else {
                # print("Handling client\n");
                handle_client($event->[0]);
            }
        }
    }
}

sub accept_client {
    accept(my $smtp_client_socket, $smtp_server);
    my $client_fd = fileno $smtp_client_socket;
    epoll_ctl($smtp::epoll, EPOLL_CTL_ADD, $client_fd, EPOLLIN) >= 0 || die "Can't add client socket to smtp::epoll: $!";
    $smtp::clients{$client_fd} = { smtp_socket => $smtp_client_socket, state => 'INIT' };
    # print("Accepted client\n");
    greet_client($client_fd);
}

sub greet_client {
    my ($client_fd) = @_;
    send_msg($client_fd, "220 UR HERE, IM HERE, WERE HERE");
    # print("greeted client\n");
}

sub handle_client {
    my ($client_fd) = @_;
    my $client_socket = $smtp::clients{$client_fd}{"smtp_socket"};

    my $buffer;
    recv($client_socket, $buffer, 1024, 0);
    $smtp::clients{$client_fd}{"buffer"} = $buffer;
    $smtp::clients{$client_fd}{"request"} .= $buffer;
    # print("RECEIVED FROM CLIENT: $buffer\n");
    if (length($buffer) < 1024) {
        process_request($client_fd);
    }
}

sub process_request {
    my ($client_fd) = @_;
    my $client_socket = $smtp::clients{$client_fd}{"smtp_socket"};
    my $buffer = $smtp::clients{$client_fd}{"buffer"};
    my $state = $smtp::clients{$client_fd}{"state"};
    my $request = $smtp::clients{$client_fd}{"request"};
    
    if ($state eq "INIT") {
        if ($buffer =~ /^EHLO (.*)/) {
            send_msg($client_fd, "250 Hello $1");
            $smtp::clients{$client_fd}{"state"} = "EHLO";
        } else {
            send_msg($client_fd, "500 Syntax error, command unrecognized");
        }
    } elsif ($state eq "EHLO") {
        if ($buffer =~ /^MAIL FROM:<?(.*)?<(.*\w)>?>/) { 
            send_msg($client_fd, "250 OK");
            $smtp::clients{$client_fd}{"state"} = "MAIL_FROM";
        } else {
            # print("Syntax error\n");
            send_msg($client_fd, "500 Syntax error, command unrecognized");
        }
    } elsif ($state eq "MAIL_FROM") {
        if ($buffer =~ /^RCPT TO:<?(.*)?<(.*\w)>?>/) {
            send_msg($client_fd, "250 OK");
            $smtp::clients{$client_fd}{"state"} = "RCPT_TO";
        } else {
            send_msg($client_fd, "500 Syntax error, command unrecognized");
        }
    } elsif ($state eq "RCPT_TO") {
        if ($buffer =~ /^DATA/) {
            send_msg($client_fd, "354 end with <CRLF>.<CRLF>");
            $smtp::clients{$client_fd}{"state"} = "DATA";
        } else {
            send_msg($client_fd, "500 Syntax error, command unrecognized");
        }
    } elsif ($state eq "DATA") {
        if ($request =~ /\r\n\.\r\n$/) {
            send_msg($client_fd, "250 OK");
            $smtp::clients{$client_fd}{"state"} = "QUIT";
        } else {
            read_data($client_fd);
        }
    } elsif ($state eq "QUIT") {
        if ($buffer =~ /^QUIT/) {
            send_msg($client_fd, "221 Bye");
            handle_email($client_fd);
            if (!$smtp::clients{$client_fd}) {
                return;
            }
            forward_email($client_fd);
            remove_client($client_fd);
        } else {
            send_msg($client_fd, "500 Syntax error, command unrecognized");
        }
    } else {
        # print("Unknown state: $state\n");
        send_msg($client_fd, "500 Syntax error, command unrecognized");
    }
}

sub forward_email {
    my ($client_fd) = @_;

    my $to = $smtp::clients{$client_fd}{"to"};
    my $mx_addr = get_mx_exchange($to);
    if (!$mx_addr) {
        return;
    }
    my $from = $smtp::clients{$client_fd}{"from"};
    my $srs_from = generate_srs_from($from);
    my $username = (split /@/, $from)[0];
    $username = parse_username($username);
    my $to_username = (split /@/, $to)[0];
    $to_username = parse_username($to_username);
    # my $username = $from;

    socket(my $mx_socket, AF_INET, SOCK_STREAM, 0);
    connect($mx_socket, sockaddr_in(25, inet_aton($mx_addr))) || do {
        warn "Can't connect to MX server: $!";
        return;
    };

    # print("BODY: $smtp::clients{$client_fd}{'body'}\n");
    my ($header, $content) = split(/\r\n\r\n/, $smtp::clients{$client_fd}{"body"}, 2);

    $smtp::clients{$client_fd}{"content"} = $content;
    if (!$content) {
        return;
    }
    my $content_type = "Content-Type: text/html; charset=UTF-8";
    smtp_send::send_email($from, $to, $smtp::clients{$client_fd}{"subject"}, $content, $content_type, $mx_addr, 25, $client_fd, $srs_from, $username, $to_username);
}

sub parse_username {
    my ($username) = @_;
    $username =~ s/\./ /g;
    $username =~ s/\b(\w)/\U$1/g;
    return $username;
}

sub generate_srs_from {
    my ($from) = @_;

    my ($user, $domain) = split /@/, $from;

    my $hmac = Digest::HMAC->new($secret_key, "Digest::SHA");
    my $hash = $hmac->add($user . $domain)->hexdigest;
    my $srs_hash = substr($hash, 0, 8); 

    $domain =~ s/\./=/;

    my $srs_addr = "SRS0+$srs_hash+$domain=$user\@$aioPerlDomain";

    # print("SRS ADDR: $srs_addr\n");
    return $srs_addr;
}

sub get_mx_exchange {
    my ($to) = @_;

    # print("to: $to\n");
    my $domain = (split /@/, $to)[1];
    # print("DOMAIN: $domain\n");
    my @mx = mx($domain);
    foreach my $mx (@mx) {
        # print("MX: $mx\n");
        # foreach my $key (keys %$mx) {
            # print("$key: $mx->{$key}\n");
        # }
    }
    my $mx_record = $mx[0];
    if (!$mx_record) {
        warn "No MX record found for $domain";
        return;
    }
    my $mx_exchange = $mx_record->exchange;
    # print("MX EXCHANGE: $mx_exchange\n");
    if (!$mx_exchange) {
        warn "No MX record found for $domain";
        return;
    }
    return $mx_record->exchange;
}

sub handle_email {
    my ($client_fd) = @_;
    my $client_socket = $smtp::clients{$client_fd}{"smtp_socket"};
    my $request = $smtp::clients{$client_fd}{"request"};
    # print("Handling email\n");
    # print("REQUEST: \r\n$request\n"); 
    my $from;
    my $to;
    my $subject;
    my $body;
    if ($request =~ /MAIL FROM:<([^>]*)>/) {
        $from = $1;
        $smtp::clients{$client_fd}{"from"} = $from;
        # print "From: $from\n";
    }
    if ($request =~ /TO:\s*<?([^>\r\n]*)>?/) {
        $to = $1;
        $smtp::clients{$client_fd}{"to"} = $to;
        # print "To: $to\n";
    }
    if ($request =~ /DATA\r\n(.*?)\r\n\.\r\n/s) {
        $body = $1;
        $smtp::clients{$client_fd}{"body"} = $body;
        # print "Body: $body\n";
        if ($body =~ /Subject:\s*(.*?)\r\n/s) {
            $subject = $1;
            $smtp::clients{$client_fd}{"subject"} = $subject;
            # print "Subject: $subject\n";
        }
    }

    # print("TO: $to\n");
    if (!$body || !$subject || !$to) {
        # print("Invalid email\n");
        return;
    }
    $smtp::clients{$client_fd}{"to"} = $to;
    
    create_email($body, $subject, $to);
}

sub remove_client {
    my ($client_fd) = @_;
    delete $smtp::clients{$client_fd};
    close($client_fd);
}

sub create_email {
    my ($body, $subject, $to) = @_;
    # print("TO: $to\n");
    my $base_dir = getcwd();
    my $email_dir = "$base_dir/Data/Emails";
    if (!-d $email_dir) {
        mkdir($email_dir) or do {
            warn "Could not create directory: $!";
            return;
        };
    }
    $email_dir = "$email_dir/$to";
    if (!-d $email_dir) {
        mkdir($email_dir) or do {
            warn "Could not create directory: $!";
            return;
        };
    }
    my $email_file = "$email_dir/${subject}" . time() . ".txt";
    open(my $fh, '>', $email_file) or do {
        warn "Could not open file '$email_file' $!";
        return;
    };
    print $fh $body;
    close($fh);
    # print("SAVED EMAIL TO $email_file\n");
}

sub send_msg {
    my ($client_identification, $msg) = @_;
    my $client_socket;
    $client_socket = get_socket($client_identification);
    if (!$client_socket) {
        return;
    }
    # print("Sending $msg\n");
    send($client_socket, "$msg\r\n", 0);
}

sub send_and_receive {
    my ($client_identification, $msg, $sender_fd) = @_;
    my $client_socket;
    $client_socket = get_socket($client_identification);
    if (!$client_socket) {
        return;
    }
    send_msg($client_socket, $msg);
    # print("SENT $msg\n");
    my $buffer;
    recv($client_socket, $buffer, 1024, 0);
    # print("RECEIVED: $buffer\n");
    if ($buffer =~ /^5/) {
        # print("ERROR: $buffer\n");
        if (!try_with_gmail($client_identification, $buffer, $sender_fd)) {
            return_to_sender($client_identification, $buffer, $sender_fd);
        }
    }
    return $buffer;
}

sub try_with_gmail {
    my ($client_identification, $error, $sender_fd) = @_;

    # print("SENDING WITH GMAIL\n");
    my $smtp_server = "smtp.gmail.com";
    my $port = 465;
    my $username = "aioperl.dev.info\@gmail.com";
    my $app_pw = no_upload::get_google_app_password();
    # print("APPP PW: $app_pw\n");

    my $smtp = Net::SMTP::SSL->new(
        $smtp_server,
        Port => $port,
        Debug => 1,
    ) or die "Can't connect to $smtp_server: $!";

    unless ($smtp->auth($username, $app_pw)) {
        warn "Authentication failed: " . $smtp->message();
        return 0;
    }

    my $from = $smtp::clients{$sender_fd}{"from"};
    my $to = $smtp::clients{$sender_fd}{"to"};
    my $subject = $smtp::clients{$sender_fd}{"subject"};
    my $info = "Info: Failed delivering from $from to you normally because wihtout Domain I cant forward it via aioperl.de server.<br> 
    Thats why it was sent via temporary Gmail. <br><br>
    EMAIL STARTS HERE:<br>
    From: $from<br>
    To: $to<br>
    Subject: $subject<br><br>                                                                       ";
    $smtp::clients{$sender_fd}{"content"} =~ s/(<body[^>]*>)/$1\n$info\n/;
    my $content = $smtp::clients{$sender_fd}{"content"};

    $smtp->mail($from);
    $smtp->to($to);
    $smtp->data();
    $smtp->datasend("To: $to\n");
    $smtp->datasend("From: $from\n");
    $smtp->datasend("Subject: $subject\n");
    $smtp->datasend("Content-Type: text/html; charset=UTF-8\n");
    $smtp->datasend("\n");
    $smtp->datasend("$content\n");
    $smtp->dataend();

    $smtp->quit;
    return 1;
}

sub return_to_sender {
    my ($client_identification, $error, $sender_fd) = @_;

    my $client_fd = get_client_fd($client_identification);
    if (!$client_fd) {
        return;
    }

    $client_fd = $sender_fd;

    # print("CLIENT FD: $client_fd\n");

    # $single_return = 1;

    my $to = $smtp::clients{$client_fd}{"from"};
    my $mx_exchange = get_mx_exchange($to);
    my $failed_to = $smtp::clients{$client_fd}{"to"};

    # print("READ HERE\n");
    # print("$to\n");
    # print("$failed_to\n");

    my $bounce_message = <<"Bounce";
Unaible to deliver mail to <$failed_to>: \r\n\r\n$error
Bounce

    smtp_send::send_email($mail::mail_daemon, $to, "Delivery Failed: $failed_to", $bounce_message, undef, $mx_exchange, 25, $client_fd);
}

sub get_client_fd {
    my ($client_identification) = @_;
    if ($client_identification =~ /GLOB/) {
        return fileno $client_identification;
    }
    return $client_identification;
}

sub get_socket {
    my ($client_identification) = @_;
    my $client_socket;
    if ($client_identification =~ /GLOB/) {
        $client_socket = $client_identification;
    } else {
        $client_socket = $smtp::clients{$client_identification}{"smtp_socket"};
    }
    if (!$client_socket) {
        # print("Client socket not found\n");
        return;
    }
    return $client_socket;
}

sub read_data {
    my ($client_fd) = @_;   
    my $client_socket = get_socket($client_fd);

    my $buffer;
    recv($client_socket, $buffer, 1024, 0);
    $smtp::clients{$client_fd}{"request"} .= $buffer;
    process_request($client_fd);
}
1;