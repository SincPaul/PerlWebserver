package friend_websocket;

use strict;
use warnings;

use JSON;

my %friend_types = (
    "get_friend_status" => \&get_friend_status,
);

sub handle_before_upgrade {
    my ($client_socket) = @_;

    if (!$main::user) {
        print("NOT UPGRADING\n");
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_401("Unauthorized"));
        main::remove_client_complete(fileno $client_socket);
        return;
    }
    print("UPGRADING\n");
    return 1;
}

sub connect_to_ws {
    # set status to online
    # notify friends

    my ($client_socket) = @_;

    if (!$main::user) {
        print("CLOSING FRIEND WS\n");
        websocket_utils::close_frame($client_socket, 1002, "no user");
        main::remove_client_complete(fileno $client_socket);
        return;
    }
    print("I'M $main::user->{displayname}\n");

    print("CONNECTING TO FRIEND WS\n");
    push @{$epoll::clients{online}{friends}{$main::user->{uuid}}}, $client_socket;
    print("added $main::user->{displayname} to online\n");
    websocket_utils::add_to_active_connections($client_socket, "Friend WS");

    my $friends_json = friend_utils::get_friends($client_socket, $main::user->{uuid});
    if (!$friends_json) {
        return;
    }
    my $friends_ref = decode_json($friends_json);
    if (!$friends_ref) {
        return;
    }
    print("FRIENDS: " . ($friends_ref) . "\n");
    foreach my $friend (@$friends_ref) {
        print("FRIEND2: " . encode_json($friend) . "\n");
        if (exists $epoll::clients{online}{friends}{$friend->{UserId}}) {
            my $message = {
                "type"   => "friend_status",
                "status" => "online",
                "uuid"   => $main::user->{uuid}
            };
            my $json_message = encode_json($message);
            my $ws_response = websocket_utils::encode_frame($json_message);
            
            my @friend_sockets = @{$epoll::clients{online}{friends}{$friend->{UserId}}};
            foreach my $friend_socket (@friend_sockets) {
                print("FRIENDS SOCKET: $friend_socket\n");
                send($friend_socket, $ws_response, 0);
                print("SENT FRIEND STATUS\n");
            }
        }
    }
    main::epoll_loop();
}

sub handle_friends {
    my ($message, $client_socket) = @_;

    if (!$main::user) {
        print("CLOSING FRIEND WS\n");
        websocket_utils::close_frame($client_socket, "no user");
        main::remove_client_complete(fileno $client_socket);
        return;
    }

    my $type = $message->{type};
    print("MESSAGE TYPE: $type\n");

    if (!$friend_types{$type}) {
        print("CLOSING FRIEND WS\n");
        websocket_utils::close_frame($client_socket, "invalid type");
        main::remove_client_complete(fileno $client_socket);
        return;
    }

    $friend_types{$type}($message, $client_socket);
}

sub remove_from_online {
    # set status to offline
    # notify friends

    my ($client_socket) = @_;
    $main::user = $epoll::clients{fileno($client_socket)}{user};
    if (!$main::user) {
        print("CLOSING FRIEND WS\n");
        websocket_utils::close_frame($client_socket, "no user");
        main::remove_client_complete(fileno $client_socket);
        return;
    }

    print("REMOVING FROM ONLINE\n");
    # @{$epoll::clients{online}{$main::user->{uuid}}} = grep { $_ != $client_socket } @{$epoll::clients{online}{$main::user->{uuid}}};
    my @delete_indexes = grep{ $epoll::clients{online}{friends}{$main::user->{uuid}}[$_] eq $client_socket } 0..$#{$epoll::clients{online}{friends}{$main::user->{uuid}}};
    my $removed_items = 0;
    foreach my $index (@delete_indexes) {
        splice(@{$epoll::clients{online}{friends}{$main::user->{uuid}}}, $index-$removed_items, 1);
        $removed_items++;
    }
    close($client_socket);
    print("CLOSED FRIEND WS\n");
    print($client_socket . "\n");
    main::remove_client_complete(fileno $client_socket);
    if (@{$epoll::clients{online}{friends}{$main::user->{uuid}}} > 0) {
        print("STILL ONLINE\n");
        print("SOCKETS: " . join(", ", @{$epoll::clients{online}{friends}{$main::user->{uuid}}}) . "\n");
        main::epoll_loop();
        return;
    }
    print("SOCKETS: " . join(", ", @{$epoll::clients{online}{friends}{$main::user->{uuid}}}) . "\n");

    delete $epoll::clients{online}{friends}{$main::user->{uuid}};
    my $friends_json = friend_utils::get_friends($client_socket, $main::user->{uuid});
    if (!$friends_json) {
        return;
    }
    my $friends_ref = decode_json($friends_json);
    if (!$friends_ref) {
        return;
    }
    foreach my $friend (@$friends_ref) {
        if (exists $epoll::clients{online}{friends}{$friend->{UserId}}) {
            my $message = {
                "type"   => "friend_status",
                "status" => "offline",
                "uuid"   => $main::user->{uuid}
            };
            my $json_message = encode_json($message);
            my $ws_response = websocket_utils::encode_frame($json_message);
            
            my @friend_sockets = @{$epoll::clients{online}{friends}{$friend->{UserId}}};
            foreach my $friend_socket (@friend_sockets) {
                send($friend_socket, $ws_response, 0);
            }
        }
    }
}

sub get_friend_status {
    my ($message, $client_socket) = @_;

    my $user_id = $message->{userId};
    if (!$user_id) {
        websocket_utils::close_frame($client_socket, "no userId");
        main::remove_client_complete(fileno $client_socket);
        return;
    }

    my $status = "offline";
    if (exists $epoll::clients{online}{friends}{$user_id}) {
        $status = "online";
    }

    my %response = (
        "type"   => "friend_status",
        "status" => $status,
        "uuid"   => $user_id
    );
    print "Friend status response: " . encode_json(\%response) . "\n";
    my $json_response = encode_json(\%response);
    my $ws_response = websocket_utils::encode_frame($json_response);
    send($client_socket, $ws_response, 0);
}
1;