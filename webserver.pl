use strict;
use warnings;

use Socket;
use JSON;
use Cwd;
use URI::Escape qw(uri_unescape);
use IO::Epoll;


use lib '.';
use HTTP_RESPONSE;
use html_pages;

$SIG{PIPE} = 'IGNORE';

my $cookie_language;
$main::max_storage = 1*1024*1024*1024; # 1GB
my $cookie_dark_mode;
my $accept_language;
$cookie::empty_cookie = "session=; expires=Thu, 01 Jan 1970 00:00:00 GMT";
my $is_post;
my $user;
my $is_shutdown = 0;
my $port = 80;
my $udp_port = 8080;
$server::storage_bottleneck = 0.8;
# my %memory::spectate_games;
$server::ip = connection_utils::get_server_ip();
print("SERVER IP: $server::ip\n");
if (!defined $server::ip) {
    die "Can't get server ip\n";
}

my @skip_routes = (
    "/logout",
    "/verify/email",
    "/change_language",
    "/dark_mode",
    "/add/email",
    "/unlink_email",
    "/change_email",
    "/resend_verification_email"
);

my %index_router = (
    "/" => \&get_index_page::get_index,

    "/ownuser" => \&get_users::get_main_user,

    "/favicon.ico" => \&get_favicon::get_favicon,

    "/about" => \&get_about_page::get_about,

    "/updatelog" => \&get_update_log_page::get_update_log,

    "/friends" => \&get_friends::get_friends,
    "/friends/requests" => \&get_friends::get_friend_requests,
    "/friends/blocked" => \&get_friends::get_blocked_users,
    
    "/login" => \&get_login_page::get_login,
    "/register" => \&get_register_page::get_register,
    "/logout" => \&logout_user::get_logout,
    
    "/profile" => \&get_profile_pages::get_profile,
    "/profile/ploud" => \&get_profile_pages::get_profile_ploud,
    "/profile/ploud/upload" => \&get_profile_pages::get_profile_ploud_upload,
    "/profile/ploud/download" => \&post_profile_pages::post_profile_ploud_download,
    "/profile/ploud/delete" => \&post_profile_pages::post_profile_ploud_delete,
    "/profile/ploud/upgrade" => \&get_profile_pages::get_profile_ploud_upgrade,

    "/data/get_server_storage" => \&user_utils::get_server_storage_json,
    
    "/blog" => \&get_blog_pages::get_blog_index,
    "/blog/view" => \&get_blog_pages::get_blog_view,
    "/blog/create" => \&get_blog_pages::get_blog_create,
    "/blog/announcement/edit" => \&get_blog_pages::get_announcement_edit,
    "/blog/announcement/deactivate" => \&get_blog_pages::announcement_switch_status,
    "/blog/announcement/activate" => \&get_blog_pages::announcement_switch_status,
    "/blog/announcement/create" => \&get_blog_pages::get_announcement_create,
    "/blog/announcement/delete" => \&get_blog_pages::get_announcement_delete,
    "/blog/announcements/manage" => \&get_blog_pages::get_blog_announcements_manage,

    "/gameroom" => \&get_gameroom_page::get_gameroom,
    "/gameroom/memory" => \&get_memory_pages::get_memory,
    "/gameroom/memory/src" => \&get_memory_pages::get_memory_src,
    # "/gameroom/memory/src/card" => \&get_memory_pages::get_memory_src_card,
    "/gameroom/memory/alone" => \&get_memory_pages::get_memory_alone,
    "/gameroom/memory/2player" => \&get_memory_pages::get_memory_2player,
    "/gameroom/memory/2player/waiting" => \&get_memory_pages::get_memory_2player_waiting,
    "/gameroom/memory/restart" => \&get_memory_pages::get_memory_restart,
    "/gameroom/memory/end" => \&get_memory_pages::get_memory_end,
    "/gameroom/memory/spectate" => \&get_memory_pages::get_memory_spectate,

    "/fonts" => \&load_fonts::get_fonts,
    "/externaljs" => \&load_js::get_external_js,

    "/calender" => "just chilling",

    "/verify" => "just chillingV2",

    "/change_email" => \&get_change_email::get_change_email,

    
    "/admin" => \&get_admin_page::get_admin,
    "/admin/users" => \&get_admin_users_pages::get_admin_users,
    "/admin/users/edit" => \&get_admin_users_pages::get_admin_edit_user,
    "/admin/users/view" => \&get_admin_users_pages::get_admin_view_user,
    "/admin/users/ban" => \&get_admin_users_pages::get_admin_ban_user,
    "/admin/users/delete" => \&get_admin_users_pages::get_admin_delete_user,

    "/admin/updatelog" => \&get_admin_update_log_manage::get_admin_update_log_manage,
    "/admin/updatelog/add" => \&get_admin_update_log_manage::get_admin_update_log_add,
    "/admin/updatelog/edit" => \&get_admin_update_log_manage::get_admin_update_log_edit, 
    "/admin/updatelog/delete" => \&get_admin_update_log_manage::get_admin_update_log_delete, 

    "/admin/gamelauncher" => \&get_admin_game_launcher::get_admin_game_launcher,
    "/admin/gamelauncher/add" => \&get_admin_game_launcher::get_admin_game_launcher_add,
    "/admin/gamelauncher/add/new" => \&get_admin_game_launcher::get_admin_game_launcher_add_new,
    "/admin/gamelauncher/edit" => \&get_admin_game_launcher::get_admin_game_edit,

    "/support" => \&get_support_pages::get_starting_page,
    "/support/request/new" => \&support_utils::handle_new_request,

    "/streaming" => \&get_streaming_pages::get_streaming_home,
    "/streaming/videos" => \&get_streaming_pages::get_streaming_videos,
    "/streaming/video/comments" => \&get_streaming_pages::get_streaming_video_comments,
    "/streaming/upload" => \&get_streaming_pages::get_streaming_upload,
    "/streaming/watch" => \&get_streaming_pages::get_streaming_watch,
    "/streaming/video/src" => \&get_streaming_pages::get_streaming_video_src,
    "/streaming/image/src" => \&get_streaming_pages::get_streaming_image_src,
    "/streaming/image/channel_icon" => \&get_streaming_pages::get_streaming_image_channel_icon,
    "/streaming/image/channel_banner" => \&get_streaming_pages::get_streaming_image_channel_banner,
    "/streaming/channel" => \&get_streaming_pages::get_streaming_channel,
    "/streaming/manage/channel" => \&get_streaming_pages::get_streaming_manage_channel,

    "/get/users" => \&get_users::get_users,

    "/gamelauncher/gamelist" => \&csharp_game::get_game_list,
    "/gamelauncher/gamestats" => \&csharp_game::get_game_stats,
    "/gamelauncher/download" => \&csharp_game::download_game,

    "/server/ip" => \&get_server_ip::get_server_ip,
);

my %post_router = (
    "/add/email" => \&email_utils::post_add_email,

    "/login" => \&login_user::post_login,
    "/login/launcher" => \&login_user::post_login_launcher,
    "/register" => \&register_user::post_register,
    "/register/launcher" => \&register_user::post_register_launcher,
    "/logout" => \&logout_user::get_logout,

    "/profile/ploud/upload" => \&post_profile_pages::post_profile_ploud_upload,
    "/profile/ploud/delete" => \&post_profile_pages::post_profile_ploud_delete,
    "/profile/ploud/download" => \&post_profile_pages::post_profile_ploud_download,
    "/profile/ploud/upgrade" => \&post_profile_pages::post_profile_ploud_upgrade,

    "/blog/create" => \&post_blog_pages::post_blog_create,
    "/blog/announcement/create" => \&post_blog_pages::post_announcement_create,

    "/shutdown" => \&get_shutdown_page::get_shutdown,
    # "/shutdown" => \&get_shutdown,

    "/change_language" => \&post_preferences::post_change_language,
    "/dark_mode" => \&post_preferences::post_dark_mode,
    
    "/admin/users" => \&post_admin_users_pages::post_admin_users,
    "/admin/users/edit" => \&post_admin_users_pages::post_admin_edit_user,
    "/admin/users/ban" => \&post_admin_users_pages::post_admin_ban_user,
    "/admin/users/delete" => \&post_admin_users_pages::post_admin_delete_user,

    "/admin/updatelog/add" => \&post_admin_update_log_manage::post_admin_update_log_add,
    "/admin/updatelog/edit" => \&post_admin_update_log_manage::post_admin_update_log_edit, 
    "/admin/updatelog/delete" => \&post_admin_update_log_manage::post_admin_update_log_delete,

    "/admin/gamelauncher/initialize" => \&post_admin_game_launcher::post_admin_initialize_game,
    "/admin/gamelauncher/upload/github" => \&post_admin_game_launcher::post_admin_upload_github,
    "/admin/gamelauncher/publish/github" => \&post_admin_game_launcher::post_admin_publish_github,

    "/important/contact_devs" => \&post_contact_devs::post_contact_devs,

    "/unlink_email" => \&email_utils::post_unlink_email,

    "/resend_verification_email" => \&email_utils::post_resend_verification_email,

    "/update/streaming/manage/channel/" => \&post_streaming_pages::post_streaming_manage_channel,
    "/streaming/channel" => \&post_streaming_pages::post_streaming_channel,
    "/update/streaming/video" => \&post_streaming_pages::post_streaming_video,
    "/update/streaming/video/comments" => \&post_streaming_pages::post_streaming_video_comments,
    "/update/streaming/video/replies" => \&post_streaming_pages::post_streaming_video_replies,

    "/friends/request" => \&post_friends::post_friend_request,
);

print("Creating main::Epoll\n");
$main::epoll = epoll_create(1024) || die "Can't create main::epoll: $!";

print("Creating socket\n");
socket(
    my $server, 
    AF_INET, 
    SOCK_STREAM, 
    0) || die "Can't create socket: $!";


print("Setting socket options\n");
setsockopt($server, SOL_SOCKET, SO_REUSEADDR, 1) || die "Can't set socket options: $!";
print("Binding to port $port\n");
bind($server, sockaddr_in($port, INADDR_ANY)) || die "Can't bind: $!";

print("Starting SMTP Server\n");
smtp_utils2::start_smtp_server();

print("Listening on port $port\n");
listen($server, 5) || die "Can't listen: $!";

print("Accepting connections\n");

# my $base_dir = getcwd();
# my $update_log_file = "$base_dir/Data/UpdateLog/update_log.json";
# github_utils::push_to_github($update_log_file);


# print("Creating UDP Socket\n");
# socket(
#     my $udp_socket,
#     AF_INET,
#     SOCK_DGRAM,
#     0) || die "Can't create udp socket: $!";

# print("Binding UDP Socket to port $udp_port\n");
# bind($udp_socket, sockaddr_in($udp_port, INADDR_ANY)) || die "Can't bind udp socket: $!";


epoll_ctl($main::epoll, EPOLL_CTL_ADD, fileno $server, EPOLLIN) >= 0 || die "Can't add server socket to main::epoll: $!";
# epoll_ctl($main::epoll, EPOLL_CTL_ADD, fileno $udp_socket, EPOLLIN) >= 0 || die "Can't add udp socket to main::epoll: $!";
# sleep(2);
# smtp_send::send_email("paul.geisthardt\@sinc.de", "paul.geisthardt\@sinc.de", "Test", "Test2");
epoll_loop();


# my %epoll::clients;
my %user_in_queue;

sub epoll_loop {
    while (1) {
        # print("Waiting for events\n");
        my $events = epoll_wait($main::epoll, 10, -1);
        # print("Received events\n");
        $main::user = undef;
        for my $event (@$events) {
            if ($event->[0] == fileno $server) {
                my $client_addr = accept(my $client_socket, $server);
                my ($client_port, $client_ip) = sockaddr_in($client_addr);
                my $client_ip_str = inet_ntoa($client_ip);
                # print("ACCEPTED NEW CONNECTION FROM $client_ip_str:$client_port\n");
                # my $geo_location = ip_utils::get_geolocation($client_ip_str);
                # print("ACCEPTED NEW CONNECTION\n");
                # print("CLIENT SOCKET:" .$client_socket . "\n");
                # print("CLIEND FD: " . fileno($client_socket) . "\n");
                $epoll::clients{fileno($client_socket)} = {};
                $epoll::clients{fileno($client_socket)}{"socket"} = $client_socket;
                $epoll::clients{fileno($client_socket)}{"ip"} = $client_ip_str;
                $epoll::clients{fileno($client_socket)}{"port"} = $client_port;
                # $epoll::clients{fileno($client_socket)}{geo_location} = $geo_location;

                # print("ADDING CLIENT '" . fileno($client_socket) . "'\n$client_socket\n");
                epoll_ctl($main::epoll, EPOLL_CTL_ADD, fileno $client_socket, EPOLLIN) >= 0 || die "Can't add client socket to main::epoll: $!";
                $epoll::clients{fileno($client_socket)}{"has_in"} = 1;

            # } elsif ($event->[0] == fileno $udp_socket) {
                # print("RECEIVED UDP PACKET\n");
            #     die;
            } elsif ($event->[1] & EPOLLIN) {
                # print("Handling client\n");
                handle_client($event->[0]);
            } elsif ($event->[1] & EPOLLOUT) {
                # print("Handling filestream\n");
                handle_filestream($event->[0]);
            } else {
                # print("Unknown event\n");
            }
        }
    }
}

close($server);


sub handle_client {
    my ($client_fd) = @_;
    my $client_socket = $epoll::clients{$client_fd}{"socket"};
    if (!$main::user) {
        $main::user = $epoll::clients{$client_fd}{main_user};
    }
    # print("CLIENT SOCKET: $client_socket\n");
    $main::client_socket = $client_socket;
    if ($epoll::clients{$client_fd}{"is_tls"}) {
        print("IS TLS\n");
        https_utils::handle_tls($client_socket);
    }

    if (!$epoll::clients{$client_fd}{"content_length"}) {
        connection_utils::get_client_data($client_fd, $client_socket);
    }

    if ($epoll::clients{$client_fd}{"is_ws"}) {
        websocket_utils::handle_websocket_communication($client_fd);
        return;
    }

    if ($epoll::clients{$client_fd}{"is_upload"}) {
        upload_utils::handle_upload($client_fd);
        return;
    }

    if (!$epoll::clients{$client_fd}{"header"}) {
        # print("1");
        $epoll::clients{$client_fd}{"is_ws"} = 1;
        websocket_utils::handle_websocket_communication($client_fd);
        return;
    }

    if ($epoll::clients{$client_fd}{"header"} =~ /Sec-WebSocket-Version: (.*)\r\n/) {
        # print("2");
        websocket_utils::handle_websocket_request($client_socket, $epoll::clients{$client_fd}{"header"});
        return;
    } else {
        connection_utils::handle_client_data($client_fd, $client_socket);
    }

    # if (!$buffer) {
    #     epoll_ctl($main::epoll, EPOLL_CTL_DEL, $client_fd, 0) >= 0 || die "Can't remove client socket from main::epoll: $!";
    #     close($client_socket);
    #     delete $epoll::clients{$client_fd};
    #     return;
    # }
}

sub handle_filestream {
    my ($client_fd) = @_;
    # print("CLIENT FD: $client_fd\n");

    my $client_socket = $epoll::clients{$client_fd}{"socket"};
    my $filestream = $epoll::clients{$client_fd}{"filestream"};
    my $fh = $filestream->{file};
    my $file_size = $filestream->{file_size};
    my $chunk_size = $filestream->{chunk_size};
    my $file_pos = $filestream->{file_pos};

    # print("FH: $fh\n");
    # print("FILE SIZE: $file_size\n");
    my $buffer;
    # sysseek $fh, $file_pos, 0;
    sysread $fh, $buffer, $chunk_size;
    # sysread($filestream->{file}, $buffer, $filestream->{chunk_size}, $filestream->{file_pos});
    $filestream->{file_pos} += length($buffer);
    # print("LENGTH BUFFER: " . length($buffer) . "\n");
    # print("FILE POS: $filestream->{file_pos}\n");
    # print("SENDING BUFFER\n");
    my $bytes_sent = send($client_socket, $buffer, 0);
    if (!defined $bytes_sent) {
        warn "Failed to send data: $!";
        remove_client_complete($client_fd);
        return;
    }
    # print("FINISHED SENDING BUFFER\n");
    if ($filestream->{file_pos} == $filestream->{file_size}) {
        close($fh);
        print("FILESTREAM COMPLETE\n");
        remove_client_out($client_fd);
    }
}

sub remove_client_in {
    my ($client_fd) = @_;
    $epoll::clients{$client_fd}{"has_in"} = 0;
    # print("removing client in\n");

    if (!$epoll::clients{$client_fd}{"has_out"}) {
        remove_client_complete($client_fd);
        return;
    } 
    # epoll_ctl($main::epoll, EPOLL_CTL_MOD, $client_fd, EPOLLOUT) >= 0 or do {
        # warn "Can't add client socket to main::epoll: $!";
        # remove_client_complete($client_fd);
        # return;
    # };
    # else {
    #     delete $epoll::clients{$client_fd}{"header"};
    #     delete $epoll::clients{$client_fd}{"content_length"};
    #     delete $epoll::clients{$client_fd}{"bytes_read"};
    #     delete $epoll::clients{$client_fd}{"more"};
    #     delete $epoll::clients{$client_fd}{"tries"};
    #     delete $epoll::clients{$client_fd}{"temp_file"};
    # }
}

sub remove_client_out {
    my ($client_fd) = @_;
    $epoll::clients{$client_fd}{"has_out"} = 0;
    epoll_ctl($main::epoll, EPOLL_CTL_MOD, $client_fd, EPOLLIN) >= 0 || die "Can't add client socket to main::epoll: $!";
    # print("removing client out\n");

    if (!$epoll::clients{$client_fd}{"has_in"}) {
        remove_client_complete($client_fd);
    } else {
        delete $epoll::clients{$client_fd}{"filestream"};
    }
}

sub remove_client_complete {
    my ($client_fd) = @_;
    if (!$client_fd) {
        return;
    }
    # print("REMOVING CLIENT\n");
    if ($epoll::clients{$client_fd}{"socket"}) {
        shutdown($epoll::clients{$client_fd}{"socket"}, 2);
        close($epoll::clients{$client_fd}{"socket"});
    }
    if ($epoll::clients{$client_fd}) {
        delete $epoll::clients{$client_fd};
    }
    return;
}

sub handle_normal_request {
    my ($client_fd, $temp_file) = @_;
    $main::isLoggedIn = 0;
    $is_post = 0;
    $accept_language = 0;
    $main::user = undef;
    $main::scheme = "light";
    $cookie_language = undef;
    $cookie_dark_mode = undef;

    my $client_socket = $epoll::clients{$client_fd}{"socket"};

    $main::header = $epoll::clients{$client_fd}{"header"};
    # print("HEADER: $main::header\n");
    ($main::uri) = $main::header =~ /(?:GET|POST) (.*?) HTTP/;
    # print("URI: $main::uri\n");
    # print("1");
    my $method = handle_method($client_socket, $main::header);
    # print("2");

    # my $cookie = request_utils::get_cookie($main::header);
    # print("3");
    
    # print("4");

    # print("5");

    my $session_cookie = request_utils::get_session_cookie($main::header);
    # print("SESSION COOKIE: $session_cookie\n");
    my ($uuid, $session_id) = cookie_utils::validate_session($session_cookie);
    # print("UUID: $uuid\n");
    # print("SESSION ID: $session_id\n");

    if ($uuid) {
        if(!user_utils::exist_not_banned($client_socket, $uuid)) {
            return;
        }
        user_utils::populate_user($session_cookie);
    }
    # print("6");
    scheme_utils::set_scheme();
    language_utils::set_language();

    my $skipidy = 0;

    # print("URI: $main::uri\n");
    foreach my $route (@skip_routes) {
        # print("ROUTE: $route\n");
        if ($main::uri =~ /$route/) {
            # print("SKIPIDY\n");
            $skipidy = 1;
            last;
        }
    }
    # print("USER: " . (defined $main::user ? $main::user : "undef") . "\n");
    # print("IMAIL: " . (defined $main::user && defined $main::user->{email} ? $main::user->{email} : "undef") . "\n");
    if (defined $main::user && !$main::user->{email} && !$skipidy) {
        # print("HELLO\n");
        my $html = get_require_email::get_require_email();
        http_utils::send_response($client_socket, HTTP_RESPONSE::OK($html));
        close($client_socket);
        return;
    }
    if ($main::user && !user_utils::is_email_verified && !$skipidy) {
        my $html = get_email_not_verified::get_email_not_verified();
        # print("HELLO\n");
        http_utils::send_response($client_socket, HTTP_RESPONSE::OK($html));
        close($client_socket);
        return;
    }
    

    my $response = handle_index($client_socket, $temp_file, $method);
    # print("7");

    # print("8");
    if (!$epoll::clients{$client_fd}{"has_out"}) {
        # print("9");
        http_utils::send_response($client_socket, HTTP_RESPONSE::OK($response));
    }
    # print("SENT RESPONSE\n");
    # print("CLIENT SOCKET: $client_socket\n");
    # close($client_socket);


    if ($is_shutdown) {
        close($server);
    }
}


sub handle_method {
    my ($client_socket, $header) = @_;
    my $method;
    if (!$header) {
        return;
    }

    if ($header =~ /^GET /) {
        # print "Received a GET request\n";
        $method = "GET";
        substr($header, 0, 4) = "";
    } elsif ($header =~ /POST /) {
        $is_post = 1;
        # print "Received a POST request\n";
        $method = "POST";
        substr($header, 0, 5) = "";
    } else {
        # print "Received an unknown request\n";
        # print("REQUEST: $header\n");
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_405);
    }

    return ($method);
}


sub handle_index {
    my ($client_socket, $temp_file, $method) = @_;
    my $response;

    if ($method eq "GET") {
        $response = handle_get_index($client_socket, $temp_file);
    } elsif ($method eq "POST") {
        $response = handle_post_index($client_socket, $temp_file, $method);
    }

    if (!defined($response)) {
        # print "Received an unknown request\n";
        # print("REQUEST: $request\n");
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404);
    }

    return $response;
}

sub handle_get_index {
    my ($client_socket, $temp_file) = @_;
    my $response;

    my @sorted_routes = sort { length($b) <=> length($a) } keys %index_router;

    if ($main::header =~ /Sec-WebSocket-Version: (.*)/) {
        die "WEBSOKCET REQUEST HANDLE GET REQUEST, SHOULDNT BE HERE, FIND OUT WHY!!!!!!!!!!!\n";
        # handle_websocket_request($client_socket, $request);
        return;
    }

    my $lc_uri = lc $main::uri;
    # print("HANDLING GET REQUEST\n");
    # print("MAIN URI: $main::uri\n");
    foreach my $route (@sorted_routes) {
        $route = lc $route;
        # print "Checking route $route\n";
        if ($lc_uri =~ /^$route/) {
            # print "Received a get request for $route\n";
            if ($route eq "/verify") {
                # print("ROUTE: $route\n");
                $response = email_utils::handle_email_verification($client_socket, $main::uri);
            } elsif ($route eq "/calender") {
                $response = calender_utils::handle_calender($client_socket, $main::uri);
            } else {
                # print("ROUTE: $route\n");
                # print("INDEX ROUTER: $index_router{$route}\n");
                $response = $index_router{$route}->($client_socket, $main::uri, $temp_file);
            }
            last;
        }
    }
    # print("RESPONSE: $response\n");
    return $response;
}



sub handle_post_index {
    my ($client_socket, $temp_file) = @_;
    my $response;

    my @sorted_routes = sort { length($b) <=> length($a) } keys %post_router;

    foreach my $post_rout (@sorted_routes) {
        if ($main::uri =~ /^$post_rout/) {
            # print "Received a post request for $post_rout\n";
            $response = $post_router{$post_rout}->($client_socket, $main::uri, $temp_file);
            # $response = HTTP_RESPONSE::OK("POST request received");
            last;
        }
    }

    return $response;
}