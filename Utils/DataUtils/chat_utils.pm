package chat_utils;

use strict;
use warnings;

use JSON;
use Cwd;
use DBI;

print("CONNECTING TO CHAT DB\n");
my $chat_db = no_upload::get_chat_db();
my $chat_dbh = DBI->connect("dbi:Pg:dbname=$chat_db->{name};host=$chat_db->{host};port=$chat_db->{port}", 
                            $chat_db->{user}, $chat_db->{password}, {AutoCommit => 1, RaiseError => 1}) or die $DBI::errstr;
print("SUCCESSFULLY CONNECTED TO CHAT DB\n");

my $chat_message_create_query = 
"CREATE TABLE IF NOT EXISTS chat_messages (
    sender_id UUID NOT NULL,
    receiver_id UUID NOT NULL,
    message TEXT NOT NULL,
    time_sent TIMESTAMP NOT NULL,
    message_id SERIAL PRIMARY KEY
)";

my $unread_messages_table_query = 
"CREATE TABLE IF NOT EXISTS unread_messages (
    message_id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    sender_id UUID NOT NULL
)";

print("CREATING CHAT TABLES IF NOT EXISTS\n");
$chat_dbh->do($chat_message_create_query) or die $chat_dbh->errstr;
$chat_dbh->do($unread_messages_table_query) or die $chat_dbh->errstr;
print("SUCCESSFULLY CREATED CHAT TABLES\n");


sub send_chat_message {
    my ($message, $client_socket) = @_;

    print("SENDING CHAT MESSAGE: $message\n");
    my $sender_uuid = $message->{SenderId};
    my $receiver_uuid = $message->{ReceiverId};
    my $message_text = $message->{Message};
    my $timestamp = $message->{TimeSentTimestamp};

    if (!defined $sender_uuid || !defined $receiver_uuid || !defined $message_text || !defined $timestamp) {
        websocket_utils::send_error($client_socket, "Invalid message format");
        return;
    }

    if ($sender_uuid eq $receiver_uuid) {
        websocket_utils::send_error($client_socket, "Cannot send message to self");
        return;
    }

    if ($sender_uuid ne $main::user->{uuid}) {
        print("SENDER UUID: $sender_uuid\n");
        print("MAIN USER UUID: $main::user->{uuid}\n");
        websocket_utils::send_error($client_socket, "Invalid sender");
        return;
    }

    if (!friend_utils::are_users_friends($sender_uuid, $receiver_uuid)) {
        websocket_utils::send_error($client_socket, "Users are not friends");
        return;
    }

    my $insert_message_query =
        "INSERT INTO chat_messages (sender_id, receiver_id, message, time_sent) 
        VALUES (?, ?, ?, ?::timestamp with time zone);";
    
    my $insert_message_sth = $chat_dbh->prepare($insert_message_query);
        $insert_message_sth->execute($sender_uuid, $receiver_uuid, $message_text, $timestamp) or do {
            websocket_utils::send_error($client_socket, "Internal server error");
            print("ERROR: $DBI::errstr\n");
            return;
        };

    my $unread_messages_query = 
    "INSERT INTO unread_messages (user_id, sender_id)
    VALUES (?, ?);";
    
    my $unread_messages_sth = $chat_dbh->prepare($unread_messages_query);
    $unread_messages_sth->execute($receiver_uuid, $sender_uuid) or do {
        websocket_utils::send_error($client_socket, "Internal server error");
        print("ERROR: $DBI::errstr\n");
        return;
    };

    my $message_query = 
    "SELECT * FROM chat_messages 
    WHERE sender_id = ? AND receiver_id = ? AND time_sent = ?::timestamp with time zone;";

    my $message_sth = $chat_dbh->prepare($message_query);
    $message_sth->execute($sender_uuid, $receiver_uuid, $timestamp) or do {
        websocket_utils::send_error($client_socket, "Internal server error");
        print("ERROR: $DBI::errstr\n");
        return;
    };

    my $message_row = $message_sth->fetchrow_hashref();
    if (!$message_row) {
        websocket_utils::send_error($client_socket, "Internal server error");
        return;
    }

    my $message_id = $message_row->{message_id} + 1;
    $message_id--;  
    print("MESSAGE ID: $message_id\n");
    $message_id + 0;
    my $new_int_message_id = 0;
    $new_int_message_id += $message_id;
    print("MESSAGE ID: $message_id\n");
    my $formatted_message = {
        "SenderId" => $message_row->{sender_id},
        "ReceiverId" => $message_row->{receiver_id},
        "Message" => $message_row->{message},
        "TimeSentTimestamp" => $message_row->{time_sent},
        "MessageId" => $new_int_message_id
    };

    return $formatted_message;


    # my $base_dir = getcwd();
    # my $messages_path_receiver = "$base_dir/Data/UserData/Users/$receiver_uuid/Messages";
    # if (!-d $messages_path_receiver) {
    #     mkdir($messages_path_receiver) or do {
    #         websocket_utils::send_error($client_socket, "Internal server error");
    #         return;
    #     };
    # }
    # my $messages_path_sender = "$base_dir/Data/UserData/Users/$sender_uuid/Messages";
    # if (!-d $messages_path_sender) {
    #     mkdir($messages_path_sender) or do {
    #         websocket_utils::send_error($client_socket, "Internal server error");
    #         return;
    #     };
    # }

    # my $messages_path_receiver_sender = "$messages_path_receiver/$sender_uuid";
    # if (!-d $messages_path_receiver_sender) {
    #     mkdir($messages_path_receiver_sender) or do {
    #         websocket_utils::send_error($client_socket, "Internal server error");
    #         return;
    #     };
    # }

    # my $messages_path_sender_receiver = "$messages_path_sender/$receiver_uuid";
    # if (!-d $messages_path_sender_receiver) {
    #     mkdir($messages_path_sender_receiver) or do {
    #         websocket_utils::send_error($client_socket, "Internal server error");
    #         return;
    #     };
    # }

    # my $new_message = {
    #     "senderId" => $sender_uuid,
    #     "receiverId" => $receiver_uuid,
    #     "message" => $message_text,
    #     "TimeSentTimestamp" => $timestamp,
    #     "hasRead" => 1
    # };

    # my $messages_file_receiver = "$messages_path_receiver_sender/chat.json";
    # if (!-e $messages_file_receiver) {
    #     open my $fh, '>', $messages_file_receiver or do {
    #         websocket_utils::send_error($client_socket, "Internal server error");
    #         return;
    #     };
    #     print $fh "{}";
    #     close $fh;
    # }

    # my $messages_file_sender = "$messages_path_sender_receiver/chat.json";
    # if (!-e $messages_file_sender) {
    #     open my $fh, '>', $messages_file_sender or do {
    #         websocket_utils::send_error($client_socket, "Internal server error");
    #         return;
    #     };
    #     print $fh "{}";
    #     close $fh;
    # }

    # open my $fh, '<', $messages_file_sender or do {
    #     websocket_utils::send_error($client_socket, "Internal server error");
    #     return;
    # };

    # my $data = do { local $/; <$fh> };

    # close $fh;

    # my $json = decode_json($data);
    # my $messages = $json->{messages};


    # push(@$messages, $new_message);
    # $json->{messages} = $messages;
    # $data = encode_json($json);



    # open $fh, '>', $messages_file_sender or do {
    #     websocket_utils::send_error($client_socket, "Internal server error");
    #     return;
    # };
    # print $fh $data;
    # close $fh;


    # open my $fh, '<', $messages_file_receiver or do {
    #     websocket_utils::send_error($client_socket, "Internal server error");
    #     return;
    # };
    # my $data = do { local $/; <$fh> };
    # close $fh;

    # my $json = decode_json($data);
    # my $messages = $json->{messages};
    
    # $new_message->{hasRead} = 0;
    # push(@$messages, $new_message);
    # $json->{messages} = $messages;
    # $data = encode_json($json);

    # open $fh, '>', $messages_file_receiver or do {
    #     websocket_utils::send_error($client_socket, "Internal server error");
    #     return;
    # };
    # print $fh $data;
    # close $fh;

    # my $unread_file = "$messages_path_receiver_sender/unread.json";
    # print("UNREAD FILE: $unread_file\n");
    # if (!-e $unread_file) {
    #     open my $fh, '>', $unread_file or do {
    #         websocket_utils::send_error($client_socket, "Internal server error");
    #         return;
    #     };
    #     print $fh "{}";
    #     close $fh;
    # }

    # open my $fh, '<', $unread_file or do {
    #     websocket_utils::send_error($client_socket, "Internal server error");
    #     return;
    # };
    # my $data = do { local $/; <$fh> };
    # close $fh;

    # my $json = decode_json($data);

    # my $unread = $json->{unread};

    # if (!exists($unread->{$sender_uuid})) {
    #     $unread->{$sender_uuid} = 0;
    # }

    # $unread->{$sender_uuid}++;

    # $json->{unread} = $unread;
    # $data = encode_json($json);

    # open $fh, '>', $unread_file or do {
    #     websocket_utils::send_error($client_socket, "Internal server error");
    #     return;
    # };

    # print $fh $data;
    # close $fh;

    # websocket_utils::send_success($client_socket, "Message sent");
    
    # return $new_message;
}

sub load_chat_messages_with_user {
    my ($client_socket, $uuid, $user_uuid, $offset) = @_;
    my $limit = 50;

    my $select_messages_query = 
    "SELECT * FROM chat_messages 
    WHERE sender_id = 'c263ac09-2513-cc8b-4638-8c12c1bb9bfb' 
    OR sender_id = 'aafa5ca0-1ec5-acc7-a0aa-aa35d7724162' 
    ORDER BY time_sent DESC
    LIMIT $limit OFFSET $offset;";

    my $select_messages_sth = $chat_dbh->prepare($select_messages_query);
    $select_messages_sth->execute() or do {
        websocket_utils::send_error($client_socket, "Internal server error");
        return;
    };

    my @messages;
    while (my $row = $select_messages_sth->fetchrow_hashref()) {
        push(@messages, $row);
        print($row . "\n");
    }

    # Convert each message row to a hash with proper structure
    my @formatted_messages;
    foreach my $msg (@messages) {
        push @formatted_messages, {
            "SenderId" => $msg->{sender_id},
            "ReceiverId" => $msg->{receiver_id},
            "Message" => $msg->{message},
            "TimeSentTimestamp" => $msg->{time_sent},
            "MessageId" => $msg->{message_id}
        };
    }
    
    return \@formatted_messages;
}
1;