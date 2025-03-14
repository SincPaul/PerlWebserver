package chat_websocket;

use strict;
use warnings;

use JSON;

my %chat_indexes = (
    "chat_message" => \&handle_chat_message,
    "load_chat_messages_with_user" => \&load_chat_messages_with_user
);

sub connect_to_ws {
    my ($client_socket) = @_;
    if (!$main::user) {
        print("CLOSING CHAT WS\n");
        websocket_utils::close_frame($client_socket, 1002, "no user");
        main::remove_client_complete(fileno $client_socket);
        return;
    }

    websocket_utils::add_to_active_connections($client_socket, "Chat WS");
    push @{$epoll::clients{online}{chat}{$main::user->{uuid}}}, $client_socket;
}

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

sub handle_chat {
    my ($message, $client_socket) = @_;

    print("MESSAGE RECEIVED: $message\n");
    foreach my $key (keys %$message) {
        print("$key: $message->{$key}\n");
    }

    my $type = $message->{type};
    if (!$chat_indexes{$type}) {
        print("INVALID MESSAGE TYPE\n");
        websocket_utils::send_error($client_socket, "Invalid message type");
        return;
    }

    $chat_indexes{$type}($message, $client_socket);
}

sub handle_chat_message {
    my ($message, $client_socket) = @_;

    print("MESSAGE RECEIVED: $message\n");
    foreach my $key (keys %$message) {
        print("$key: $message->{$key}\n");
    }

    my $message_text = $message->{message};
    print("MESSAGE TEXT: $message_text\n");
    foreach my $key (keys %$message_text) {
        print("$key: $message_text->{$key}\n");
    }

    my $message = chat_utils::send_chat_message($message_text, $client_socket);
    if (!$message) {
        return;
    }

    my %sent_message = (
        "type" => "chat_message",
        "message" => $message
    );
    foreach my $key (keys %$message) {
        print("$key: $message->{$key}\n");
    }
    my $json_message = encode_json(\%sent_message);

    my $ws_response = websocket_utils::encode_frame($json_message);

    my $friend_uuid = $message->{ReceiverId};
    if (!$friend_uuid) {
        print("NO FRIEND UUID\n");
        websocket_utils::send_error($client_socket, "Invalid message format");
        return;
    }

    my @target_sockets = exists $epoll::clients{online}{chat}{$friend_uuid} ? @{$epoll::clients{online}{chat}{$friend_uuid}} : ();
    my @own_sockets = exists $epoll::clients{online}{chat}{$main::user->{uuid}} ? @{$epoll::clients{online}{chat}{$main::user->{uuid}}} : ();
    push(@target_sockets, @own_sockets);
    foreach my $target_socket (@target_sockets) {
        send($target_socket, $ws_response, 0);
    }
    # my $decoded_text = decode_json($message_text);
    # print("DECODED TEXT: $decoded_text\n");
    #my $decoded_message = decode_json($message);
    #print("DECODED MESSAGE: $decoded_message\n");
    main::epoll_loop();
}

sub load_chat_messages_with_user {
    my ($message, $client_socket) = @_;

    print("MESSAGE RECEIVED: $message\n");
    foreach my $key (keys %$message) {
        print("$key: $message->{$key}\n");
    }

    my $friend_uuid = $message->{friendId};
    if (!$friend_uuid) {
        print("NO FRIEND UUID\n");
        websocket_utils::send_error($client_socket, "Invalid message format");
        return;
    }

    my $offset = $message->{offset};

    my $user_id = $message->{userId};
    if (!$user_id) {
        print("NO USER ID\n");
        websocket_utils::send_error($client_socket, "Invalid message format");
        return;
    }

    if ($user_id ne $main::user->{uuid}) {
        print("INVALID USER ID\n");
        websocket_utils::send_error($client_socket, "Invalid user id");
        return;
    }

    my $messages = chat_utils::load_chat_messages_with_user($client_socket, $main::user->{uuid}, $friend_uuid, $offset);
    if (!$messages) {
        return;
    }

    my %sent_message = (
        "type" => "loaded_chat_messages",
        "messages" => $messages,
        "amount" => scalar @$messages,
        "offset" => 0+$offset,
        "friendId" => $friend_uuid
    );
    my $json_message = encode_json(\%sent_message);
    my $ws_response = websocket_utils::encode_frame($json_message);
    send($client_socket, $ws_response, 0);
    main::epoll_loop();
}
1;