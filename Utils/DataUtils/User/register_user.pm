package register_user;

use strict;
use warnings;

use Cwd;
use JSON;

sub post_register {
    my ($client_socket, $route, $temp_file, $is_launcher) = @_;
    my $response;
    my $username;
    my $password; 
    my $email;
    my $accept_language = "en";
    
    
    my $body = body_utils::load_temp_file($temp_file);

    my $json = decode_json($body);
    $username = $json->{username};
    $password = $json->{password};
    $email = $json->{email};
    if (user_utils::is_wide($username)) {
        $username = user_utils::encode_uri($username);
    }
    if (user_utils::is_wide($password)) {
       $password = user_utils::encode_uri($password);
    }
    my $fingerprint = $json->{fingerprint};
    my $ip = $epoll::clients{fileno($client_socket)}{ip};

    if (length($username) > 24 || length($password) > 24) {
        $response = HTTP_RESPONSE::ERROR_400("Username or password too long");
        return $response;
    }

    if (!$username || !$password) {
        $response = HTTP_RESPONSE::ERROR_400();
        return $response;
    }

    if ($main::header =~ /Accept-Language: (.*)/) {
        $accept_language = $1;
    }

    if (register_user($username, $password, $client_socket, $accept_language, $email, $is_launcher)) {
        my $cookie = cookie_utils::get_session_cookie($username);
        my $register_link = email_utils::create_email_verification_link($email, $username);

        cookie_utils::validate_session($cookie);
        # my $cookie_data = cookie_utils::get_cookie_data($request);
        # print("COOKIE DATA: $cookie_data\n");
        # my $session_cookie = cookie_utils::generate_session_cookie($username);
        # print("SESSION COOKIE: $session_cookie\n");

        # my %user_info = (
        #     username => $username,
        #     fingerprint => $fingerprint,
        #     ip => $ip,
        # );
        # my $remember_me_cookie = cookie_utils::generate_remember_me_cookie(%user_info);
        # print("REMEMBER ME COOKIE: $remember_me_cookie\n");
        # my $session_id = cookie_utils::extract_id_from_cookie($session_cookie);
        # print("SESSION ID: $session_id\n");
        # $cookie_data->{session_id} = $session_id;
        # my $remember_me_id = cookie_utils::extract_id_from_cookie($remember_me_cookie);
        # print("REMEMBER ME ID: $remember_me_id\n");
        # $cookie_data->{remember_me_id} = $remember_me_id;
        # my $cookie = cookie_utils::create_cookie($cookie_data, "UserCookie", 108000);
        # print("COOKIE: $cookie\n");
        # user_utils::populate_user($cookie);
        
        user_utils::populate_user($cookie);
        if ($is_launcher) {
            $response = HTTP_RESPONSE::OK_WITH_COOKIE("Registered, click on email to activate", $cookie);
            http_utils::send_http_response($client_socket, $response);
            return;
        }
        $response = HTTP_RESPONSE::OK_WITH_COOKIE(get_operation_finished_pages::get_registered_html($main::user->{human_username}), $cookie);
    } else {
        $response = HTTP_RESPONSE::ERROR_409("User already exists <a href=\"/register\">Try again</a>");
        # $response = HTTP_RESPONSE::ERROR_400("User already exists");
    }
    http_utils::send_http_response($client_socket, $response);
}


sub register_user {
    my ($username, $password, $client_socket, $accept_language, $email, $is_launcher) = @_;
    my $base_dir = getcwd();
    my $UserDataFolder = "$base_dir/Data/UserData";
    my $UsernameFile = "$UserDataFolder/usernames.json";
    my $uuid = create_uuid_as_string();
    # print("UUID: $uuid\n");

    if (!-d $UserDataFolder) {
        mkdir $UserDataFolder or return 0;
    }

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

    if (exists $user_to_uuid{$username}) {
        # print("User already exists\n");
        return 0;
    }

    while (exists $uuid_to_user{$uuid}) {
        $uuid = create_uuid_as_string();  
    }

    $user_to_uuid{$username} = $uuid;
    $uuid_to_user{$uuid} = $username;

    $password = user_utils::hash_password($password);

    my %data_to_save = (
        user_to_uuid => \%user_to_uuid,
        uuid_to_user => \%uuid_to_user,
    );

    open(my $file, '>', $UsernameFile) or die "Cannot open file: $!";
    print $file encode_json(\%data_to_save);
    close $file;

    # print "Username '$username' assigned UUID '$uuid'\n";

    my $foldername = "$UserDataFolder/Users/$uuid";
    my $filename = "$foldername/$uuid.json";
    if (!-d $foldername) {
        mkdir $foldername or return 0;
    }

    my $max_storage = user_utils::get_rank_stats(0, "benefits")->{max_storage};
    if (!$max_storage) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Error Setting up user"));
    }
    my $used_emails = user_utils::get_used_emails();
    if (exists $used_emails->{$email}) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Email already in use"));
        return;
    }
    # print("EMAIL: $email\n");
    # print("MAX STORAGE: $max_storage\n");
    my %user_data = (
        uuid => $uuid,
        username => $username,
        displayname => $username,
        password_hash => $password,
        email => $email,
        email_status => "pending",
        preferences => {
            language => $accept_language
        },
        role => "user",
        banned => {
            status => 0,
            reason => "",
            banned_until => 0
        },
        friends_only_uuids => {},
        friends => {},
        friend_requests => {},
        friend_requests_sent => {},
        posts => {},
        comments => {},
        notifications => {},
        messages => {},
        rank => {
            name => "bronze",
            id => 0,
            benefits => {
                max_storage => $max_storage,
                storage_used => 0,
            }
        },
    );

    my $json = encode_json(\%user_data);


    open $file, '>', $filename or do {
        warn "Cannot open file: $!"; 
        return 0;
    };
    # print $file $password . "\n";
    # print $file "user\n";
    print $file $json . "\n";
    close $file;
    # $main::user = User->new($username, $password);
    # print("User '$username' registered\n");
    
    # my $html = get_operation_finished_pages::get_logined($username);
    # http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK_WITH_COOKIES($html, $cookie, $remember_me_cookie));
    return 1;
}

sub create_uuid_as_string {
    my @chars = ('0'..'9', 'a'..'f');
    my $uuid = '';
    my @sections = (8, 4, 4, 4, 12);
    foreach my $section (@sections) {
        $uuid .= join('', map { $chars[rand @chars] } 1..$section) . '-';
    }
    $uuid =~ s/-$//; 
    return $uuid;
}

sub post_register_launcher {
    my ($client_socket, $route, $temp_file) = @_;
    my $is_launcher = 1;
    post_register($client_socket, $route, $temp_file, $is_launcher);
}

1;