package post_friends;

use strict;
use warnings;

use Cwd;
use JSON;

my %request_types = (
    "accept" => \&friend_utils::accept_friend_request,
    "decline" => \&friend_utils::decline_friend_request,
    "cancel" => \&friend_utils::cancel_friend_request,
    "add" => \&friend_utils::send_friend_request,
    "block" => \&friend_utils::block_user,
    "remove" => \&friend_utils::remove_friends,
    "unblock" => \&friend_utils::unblock_user
);
sub post_friend_request {
    my ($client_socket, $route, $temp_file) = @_;
    print($route."\n");
    print("HELLO\n");
    my $sender_uuid = $main::user->{uuid};

    my ($type) = $route =~ /friends\/request\/(.*)/;
    print("TYPE: $type\n");

    if (!$sender_uuid) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_401("Unauthorized"));
        return;
    }

    
    if (!exists $request_types{$type}) {
        print("BAD REQUEST\n");
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Bad Request"));
        return;
    }

    $request_types{$type}->($client_socket, $route, $temp_file);
    my $body = body_utils::load_temp_file($temp_file);
    if (!$body) {
        return;
    }
    my $json = decode_json($body);
    print("JsON: $json\n");
    foreach my $key (keys %$json) {
        print("$key: $json->{$key}\n");
    }
    my $target_uuid = $json->{userId};
    if (!$target_uuid) {
        my $username = $json->{username};
        if (user_utils::is_wide($username)) {
            $username = user_utils::encode_uri($username);
        }
        $target_uuid = user_utils::get_uuid_by_username($username);
    }
    if (!$target_uuid) {
        return;
    }
    notify_user($client_socket, $target_uuid, $sender_uuid, $type);
}

my %notify_types = (
    "accept" => "friend_request_accepted",
    "decline" => "friend_request_declined",
    "cancel" => "friend_request_canceled",
    "add" => "friend_request_sent",
    "block" => "user_blocked",
    "remove" => "friend_removed",
);

my %notify_messages = (
    "friend_request_accepted" => \&get_friend_request_accepted,
    "friend_request_declined" => \&get_friend_request_declined,
    "friend_request_canceled" => \&get_friend_request_canceled,
    "friend_request_sent" => \&get_friend_request_sent,
    "user_blocked" =>  \&get_user_blocked,
    "friend_removed" =>  \&get_friend_removed
);

sub notify_user {
    my ($client_socket, $target_uuid, $sender_uuid, $type) = @_;
    print("NOTIFYING USER\n");
    print("TYPE: $type\n");
    if (!$target_uuid) {
        print("NO TARGET UUID\n");
        return;
    }
    if (!exists $epoll::clients{online}{$target_uuid}) {
        print("USER NOT ONLINE\n");
        return;
    }

    if (!exists $notify_types{$type}) {
        print("BAD REQUEST\n");
        return;
    }

    my $message = $notify_messages{$notify_types{$type}}->($sender_uuid, $type, $target_uuid);
    print("MESSAGE: $message\n");
    my $json_message = encode_json($message);
    my $ws_response = websocket_utils::encode_frame($json_message);

    my @target_sockets = @{$epoll::clients{online}{$target_uuid}};
    foreach my $target_socket (@target_sockets) {
        send($target_socket, $ws_response, 0);
    }

    main::epoll_loop();
}

sub get_friend_request_accepted {
    my ($sender_uuid, $type, $target_uuid) = @_;

    my $friend = friend_utils::get_friend($target_uuid);

    my %message = (
        "type" => "friend_request_accepted",
        "user" => $friend
    );
    return \%message;
}

sub get_friend_request_declined {
    my ($sender_uuid, $type) = @_;

    my %message = (
        "type" => "friend_request_declined",
        "userId" => $sender_uuid
    );
    return \%message;
}

sub get_friend_request_canceled {
    my ($sender_uuid, $type) = @_;

    my %message = (
        "type" => "friend_request_canceled",
        "userId" => $sender_uuid
    );
    return \%message;
}

sub get_friend_request_sent {
    my ($sender_uuid, $type, $target_uuid) = @_;

    my $friend_request = friend_utils::get_received_request($target_uuid);
    print("FRIEND REQUEST: $friend_request\n");
    my %message = (
        "type" => "friend_request_sent",
        "user" => $friend_request
    );
    return \%message;
}

sub get_user_blocked {
    my ($sender_uuid, $type) = @_;

    my %message = (
        "type" => "user_blocked",
        "userId" => $sender_uuid
    );
    return \%message;
}

sub get_friend_removed {
    my ($sender_uuid, $type) = @_;

    my %message = (
        "type" => "friend_removed",
        "userId" => $sender_uuid
    );
    return \%message;
}

1;