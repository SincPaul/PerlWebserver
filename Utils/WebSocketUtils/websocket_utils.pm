package websocket_utils;

use strict;
use warnings;
use IO::Epoll;
use JSON;
use Cwd;

my %websocket_types = (
    "game" => \&game_utils::handle_game_index,
    "chat" => \&chat_websocket::handle_chat,
    "friends" => \&friend_websocket::handle_friends,
);

my %disconnect_types = (
    "Memory Queue" => \&memory_game_utils::remove_from_queue,
    "Memory Game" => \&memory_game_utils::remove_from_game,
    "Friend WS" => \&friend_websocket::remove_from_online,
);

my %handle_based_on_uri = (
    "/friends" => \&friend_websocket::connect_to_ws,
    "/chat" => \&chat_websocket::connect_to_ws,
);

my %handle_before_upgrade = (
    "/friends" => \&friend_websocket::handle_before_upgrade,
    "/chat" => \&chat_websocket::handle_before_upgrade,
);

sub receive_msg {
    my ($client_socket) = @_;
    my $client_fd = fileno $client_socket;
    # print("RECEIVING FOR CLIENT $client_fd\n");

    my $message = $epoll::clients{$client_fd}{"message"};
    if ($epoll::clients{$client_fd}{"more"} != 0) {
        # print("RECEIVING MESSAGE\n");
        recv($client_socket, my $buffer, 1024, 0);
        $message .= $buffer;
        $epoll::clients{$client_fd}{"ws_request"} .= $buffer;
        if (length($buffer) < 1024) {
            $epoll::clients{$client_fd}{"more"} = 0;
        }
    }

    if (!$message) {
        print("REMOVING DISCONNECTED CLIENT ".($client_fd)."\n");
        on_disconnect($client_socket);
        close($client_socket);
        delete $epoll::clients{$client_fd};
        main::epoll_loop();
        return;
    }

    # print("RAW MESSAGE: " . unpack("H*", $message) . ".\n");

    # my $message;
    # while (1) {
    #     recv($client_socket, my $buffer, 1024, 0);
    #     $message .= $buffer;
        # print("BONJOUR\n");
    #     last if length($buffer) < 1024;
    # }

    if ($epoll::clients{$client_fd}{"more"} != 0) {
        return;
    }

    # print("MESSAGE: $message\n");
    my $decoded_message = decode_frame($message, $client_socket);
    # print("DECODED MESSAGE: $decoded_message\n");

    # my $answer_frame = encode_frame("Hello from server");
    # send($client_socket, $answer_frame, 0);

    return $decoded_message;
}

sub encode_frame {
    my ($message) = @_;

    my $message_length = length($message);
    my $frame = "";

    if ($message_length < 125) {
        # print("ENCODING MSG UNDER 125\n");
        my $byte1 = pack("C", 0b10000001);
        $frame = pack("C", 0b10000001) . pack("C", $message_length) . $message;
    } elsif ($message_length < 65536) {
        # print("ENCODING MSG UNDER 65536\n");
        $frame = pack("C", 0b10000001) . pack("C", 126) . pack("n", $message_length) . $message;
    } else {
        # print("ENCODING MSG OVER 65536\n");
        $frame = pack("C", 0b10000001) . pack("C", 127) . pack("Q>", $message_length) . $message;
    }

    # print("FRAME: $frame\n");
    # print("DECODED FRAME: " . unpack("H*", $frame) . "\n");

    return $frame;
}

sub encode_close_frame {
    my ($close_code, $message) = @_;

    my $message_length = length($message);
    my $frame = "";

    if (!$close_code) {
        return;
    }

    $frame .= pack("n", $close_code);

    if ($message_length) {
        $frame .= $message;
    }

    if ($message_length > 125) {
        die "Message too long";
        return;
    }

    $frame = pack("C", 0b10001000) . pack("C", length($frame)) . $frame;

    return $frame;
}
        

sub decode_frame {
    my ($message, $client_socket) = @_;

    if (!$message) {
        return;
    }

    my $encoded_msg = unpack("H*", $message);
    # print("ENCODED MSG: $encoded_msg\n");

    my $byte1 = unpack("C", substr($message, 0, 1));
    # print("BYTE1: $byte1\n");
    my $fin = ($byte1 >> 7) & 0b00000001;
    my $rsv1 = ($byte1 >> 6) & 0b00000001;
    my $rsv2 = ($byte1 >> 5) & 0b00000001;
    my $rsv3 = ($byte1 >> 4) & 0b00000001;
    my $opcode = $byte1 & 0b00001111;

    # print("FIN: $fin\n");
    # print("RSV1: $rsv1\n");
    # print("RSV2: $rsv2\n");
    # print("RSV3: $rsv3\n");
    # print("OPCODE: $opcode\n");

    if ($opcode == 0x8) {
        # print("CLOSING CONNECTION\n");
        send($client_socket, pack("C", 0x88), 0);
        on_disconnect($client_socket);
        close($client_socket);
        return;
    }

    my $mask = unpack("C", substr($message, 1, 1)) >> 7 & 0b00000001;
    # print("MASK: $mask\n");

    if (!$mask) {
        # print("No mask\n");
        no_mask_error($client_socket); # ! maski error machen 1002 protocol error close
        return;
    }
    my ($payload_length, $last_byte) = get_payload_length($message);

    # print("LAST BYTE: $last_byte\n");
    # print("PAYLOAD LENGTH: $payload_length\n");

    my @masking_key = get_masking_key($message, $last_byte);
    # print("MASKING KEY: @masking_key\n");

    my $encode_data = substr($message, $last_byte+5, $payload_length);

    my $decoded_data = decode_data($encode_data, @masking_key, $payload_length);
    # print("DECODED DATA: $decoded_data\n");
    
    return $decoded_data;
}

sub no_mask_error {
    my ($client_socket) = @_;
    my $error_frame = encode_close_frame(1002, "Protocol Error");
    # print("NO MASK\n");
    send($client_socket, $error_frame, 0);
    close($client_socket);
    warn "Protocol error: No mask present in the frame";
}

sub close_frame {
    my ($client_socket, $close_code, $close_message) = @_;
    if (!$close_code) {
        return;
    }
    my $close_frame = encode_close_frame($close_code, $close_message);
    send($client_socket, $close_frame, 0);
    print("CLOSED CONNECTION\n");
    close($client_socket);
}

sub send_error {
    my ($client_socket, $error_message) = @_;
    my $error_frame = encode_frame($error_message);
    send($client_socket, $error_frame, 0);
}

sub send_success {
    my ($client_socket, $success_message) = @_;
    my $success_frame = encode_frame($success_message);
    send($client_socket, $success_frame, 0);
}

sub decode_data {
    my ($encoded_data, @masking_key, $payload_length) = @_;

    my $decoded_data = "";

    # print("ENCODED DATA: $encoded_data\n");
    my $hex_encoded = unpack("H*", $encoded_data);
    # print("ENCODED DATA: $hex_encoded\n");
    # print("LENGTH: " . length($encoded_data) . "\n");

    for (my $i = 0; $i < length($encoded_data); $i++) {
        my $byte = substr($encoded_data, $i, 1);
        my $mask_byte = $masking_key[$i % 4];
        my $decoded_byte = $byte ^ $mask_byte;
        $decoded_data .= $decoded_byte;
        # print("BYTE: " . unpack("H2", $byte) . " MASK BYTE: " . unpack("H2", $mask_byte) . " DECODED BYTE: " . unpack("H2", $decoded_byte) . "\n");
    }
    # print("DECODED DATA: $decoded_data\n");

    return $decoded_data;
}

sub get_payload_length {
    my ($message) = @_;

    my $byte2 = unpack("C", substr($message, 1, 1));
    # print("BYTE2: $byte2\n");

    my $length;
    my $last_byte;

    my $payload_length = $byte2 & 0b01111111;
    # print("PAYLOAD LENGTH: $payload_length\n");
    if ($payload_length <= 125) {
        $length = $payload_length;
        $last_byte = 1;
    } elsif ($payload_length == 126) {
        my $byte3and4 = unpack("n", substr($message, 2, 2));
        # print("BYTE3AND4: $byte3and4\n");
        $length = $byte3and4;
        $last_byte = 3;
    } elsif ($payload_length == 127) {
        my $bytes3to10 = unpack("Q", substr($message, 2, 8));
        # print("BYTES3TO10: $bytes3to10\n");
        $length = $bytes3to10;
        $last_byte = 9;
    }
    
    return ($length, $last_byte);
}

sub get_masking_key {
    my ($message, $last_byte) = @_;

    my @masking_key;
    @masking_key[0] = substr($message, $last_byte+1, 1);
    @masking_key[1] = substr($message, $last_byte+2, 1);
    @masking_key[2] = substr($message, $last_byte+3, 1);
    @masking_key[3] = substr($message, $last_byte+4, 1);
    
    foreach my $key (@masking_key) {
        # print("KEY: $key\n");
        # print("Masking Key: ", unpack("H*", $key), "\n");
    }

    return @masking_key;
}

sub handle_websocket_request {
    my ($client_socket, $request) = @_;

    # print("WEBSOCKET REQUEST\n");
    # print("REQUEST: $request\n");
    ($main::uri) = $request =~ /(?:GET|POST) (.*?) HTTP/;
    if ($request =~ /Sec-WebSocket-Version: (.*)\r\n/) {
        my $version = $1;
        if ($version ne "13") {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400_WEBSOCKET_VERSION("Unsupported WebSocket version"));
            return;
        }
    }
    if ($request =~ /Sec-WebSocket-Key: (.*)\r\n/) {
        my $key = $1;

        if ($handle_before_upgrade{$main::uri}) {
            print("checking " . $main::uri . "\n");
            if (!$handle_before_upgrade{$main::uri}->($client_socket)) {
                return;
            }
        } else {
            print("NO HANDLER for $main::uri\n");
            # print($request);
        }

        my $response = HTTP_RESPONSE::SWITCHING_PROTOCOLS_101($key);
        http_utils::send_response($client_socket, $response);
        
        # epoll_ctl($main::epoll, EPOLL_CTL_ADD, fileno $client_socket, EPOLLIN) >= 0 || die "Can't add client socket to epoll: $!";
        print("URI: $main::uri\n");
        $epoll::clients{fileno $client_socket}{uri} = $main::uri;
        $epoll::clients{fileno $client_socket}{user} = $main::user;
        print("SETTING MAIN USER FOR FD ".fileno($client_socket).": $main::user\n");
        print($epoll::clients{fileno $client_socket}{user} . "\n");

        
        if ($handle_based_on_uri{$main::uri}) {
            print("HANDLING BASED ON URI\n");
            $handle_based_on_uri{$main::uri}->($client_socket);
        } else {
            print("STINKY\n");
        }
        # print("WEBSOCKET UPGRADED\n");

        main::epoll_loop();
    }
}

sub handle_websocket_communication {
    my ($client_fd) = @_;
    # print("HANDLING WEBSOCKET COMMUNICATION\n");
    my $client_socket = $epoll::clients{$client_fd}{"socket"};
    # print("CLIENT SOCKET: $client_socket\n");
    if (!$client_socket) {
        return;
    }
    # send($client_socket, "Hello from server", 0) or die "send: $!";

    my $message = websocket_utils::receive_msg($client_socket);
    # print("MESSAGE: $message\n");
    if (!$message) {
        return;
    }
    # print("MESSAGE: $message\n");

    if ($message eq "ping") {
        my $response = encode_frame("pong");
        send($client_socket, $response, 0) or warn "Failed to send response: $!";
        return;
    }

    if (!defined $main::user) {
        print("NO MAIN USER for fd $client_fd\n");
        $main::user = $epoll::clients{$client_fd}{"user"};
        print($epoll::clients{$client_fd}{"user"} . "\n");
        print("MAIN USER: $main::user\n");
    }


    my $message_hash;
    eval {
        $message_hash = decode_json($message);
        1;
    } or do {
        warn "Invalid JSON string: $message";
    };

    my $response;

    if (!$message_hash) {
        $response = "msg: BONJOUR";
    } else {
        # print("GETTING RESPONSE\n");
        $response = get_response($message_hash, $client_socket);
    }


    if ($response && $response eq "NO RESPONSE") {
        return;
    }

    if ($response && $response eq "null") {
        return;
    }

    $response = encode_json($response);

    # print("ENCODED RESPONSE: $response\n");
    $response = websocket_utils::encode_frame($response);
    # print("SENDING RESPONSE: $response to CLIENT SOCKET $client_socket\n");
    send($client_socket, $response, 0) or warn "Failed to send response: $!";
    # my $client_socket = $epoll::clients{$client_fd};
    # my $response = HTTP_RESPONSE::OK("HELLO");
    # close($client_socket);
}


sub get_response {
    my ($message, $client_socket) = @_;
    if (ref($message) ne "HASH") {
        return("HELLO FROM SERVER");
    }

    foreach my $type (keys %websocket_types) {
        if ($message->{"wstype"} eq $type) {
            return $websocket_types{$type}->($message, $client_socket);
        }
    }

    # if ($message->{"game"} eq "memory") {
    #     return handle_memory($message, $client_socket);
    # }
}



sub on_disconnect {
    my ($client_socket) = @_;

    my $active_connections_ref = get_active_connections($client_socket);
    my @active_connections = @$active_connections_ref;

    foreach my $active_connection (@active_connections) {
        handle_disconnect($active_connection, $client_socket);
    }
    close($client_socket);
    main::remove_client_complete(fileno $client_socket);
}

sub get_active_connections {
    my ($client_socket) = @_;

    my @active_connections;

    foreach my $connection (@{$epoll::clients{fileno $client_socket}{connections}}) {
        push @active_connections, $connection;
    }

    return \@active_connections;
}


sub handle_disconnect {
    my ($active_connection, $client_socket) = @_;

    print("ACTIVE CONNECTION: $active_connection\n");
    foreach my $type (keys %disconnect_types) {
        print("TYPE: $type\n");
        if ($active_connection =~ /$type/) {
            return $disconnect_types{$type}->($client_socket, $active_connection);
        }
    }

    return 0;
}

sub add_to_active_connections {
    my ($client_socket, $connection) = @_;

    my $client_fd = fileno $client_socket;

    push @{$epoll::clients{$client_fd}{connections}}, $connection;
}
1;