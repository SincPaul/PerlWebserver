package login_user;

use strict;
use warnings;

use JSON;
use Cwd;

sub post_login {
    my ($client_socket, $route, $temp_file, $is_launcher) = @_;
    my $response;
    my $username;
    my $password; 
    my $accept_language;
    my $fingerprint;
    my $ip;

    my $body = body_utils::load_temp_file($temp_file);

    # print("BODY: $body\n");
    my $json = decode_json($body);
    $username = $json->{username};
    $password = $json->{password};
    if (user_utils::is_wide($username)) {
        $username = user_utils::encode_uri($username);
    }
    if (user_utils::is_wide($password)) {
       $password = user_utils::encode_uri($password);
    }
    if ($json->{fingerprint}) {
        $fingerprint = $json->{fingerprint};
    }
    $ip = $epoll::clients{fileno($client_socket)}{ip};

    if (!$username || !$password) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400());
    }

    if (length($username) > 24 || length($password) > 24) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Username or password too long"));
    }

    if ($main::header =~ /Accept-Language: (.*)\r/) {
        $accept_language = $1;
    }

    if (login_user($username, $password, $client_socket)) {
        # my $cookie = cookie_utils::generate_session_cookie($username);
        # my $remember_me_cookie = cookie_utils::generate_remember_me_cookie($username, $fingerprint, $ip);
        # my @cookies = ($cookie, $remember_me_cookie);
        my $cookie = cookie_utils::get_session_cookie($username);
        cookie_utils::validate_session($cookie);
        if ($is_launcher) {
            $response = HTTP_RESPONSE::OK_WITH_COOKIE("Logged in", $cookie);
            http_utils::send_http_response($client_socket, $response);
            return;
        }
        my $html = get_operation_finished_pages::get_logined($username);
        $response = HTTP_RESPONSE::OK_WITH_COOKIE($html, $cookie);
        user_utils::populate_user($cookie, $accept_language);
    } else {
        $response = HTTP_RESPONSE::OK("Invalid username or password <a href=\"/login \">Try again</a>");
    }
    http_utils::send_http_response($client_socket, $response);
}

sub login_user {
    my ($username, $password, $client_socket) = @_;
    my $base_dir = getcwd();
    my $UsernameFile = "$base_dir/Data/UserData/usernames.json";
    my %user_to_uuid; 
    my %uuid_to_user; 

    if (-e $UsernameFile) {
        open(my $file, '<', $UsernameFile) or die "Cannot open file: $!";
        my $json = do { local $/; <$file> };
        close $file;

        my $data = decode_json($json);
        %user_to_uuid = %{$data->{user_to_uuid}};
        %uuid_to_user = %{$data->{uuid_to_user}};
    }

    if (!exists($user_to_uuid{$username})) {
        return 0;
    }

    my $uuid = $user_to_uuid{$username};
    # print("UUID: $uuid\n");


    my $filename = "$base_dir/Data/UserData/Users/$uuid/$uuid.json";

    if (!-e $filename) {
        # print("FILE DOES NOT EXIST\n");
        return 0;
    }

    open my $fh, '<', $filename or do {
        warn ("Cannot open file: $!");
        return 0;
    };
    my $json = do { local $/; <$fh> };
    close $fh;

    my $data = decode_json($json);
    my $password_hash = $data->{password_hash};

    # print("PASSWORD HASH: $password_hash\n");
    if (!user_utils::verify_password($password, $password_hash)) {
        # print("PASSWORDS DO NOT MATCH\n");
        return 0;
    }

    if (!user_utils::exist_not_banned($client_socket, $uuid)) {
        # print("USER IS BANNED/DOESNT EXIST\n");
        return 0;
    }

    return 1;
}

sub post_login_launcher {
    my ($client_socket, $route, $temp_file) = @_;
    my $is_launcher = 1;
    # print("LAUNCHER LOGIN\n");
    return post_login($client_socket, $route, $temp_file, $is_launcher);
}
1;