package friend_utils;

use strict;
use warnings;

use JSON;
use Cwd;

sub send_friend_request {
    my ($client_socket, $route, $temp_file) = @_;

    my $sender_uuid = $main::user->{uuid};

    my $body = body_utils::load_temp_file($temp_file);

    my $json;
    eval {
        $json = decode_json($body);
    };
    if ($@) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Invalid JSON"));
        return;
    }

    my $friend_username = $json->{username};
    print("FRIEND USERNAME: $friend_username\n");
    if (user_utils::is_wide($friend_username)) {
        print("IS WIDE\n");
        $friend_username = user_utils::encode_uri($friend_username);
    }
    print("FRIEND USERNAME: $friend_username\n");
    my $friend_uuid = user_utils::get_uuid_by_username($friend_username);
    if (!$friend_uuid) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("User Not Found"));
        return;
    }

    if ($sender_uuid eq $friend_uuid) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Cannot send friend request to yourself"));
        return;
    }

    if (is_user_blocked($friend_uuid, $sender_uuid)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("User has blocked you"));
        return;
    }

    if (is_user_blocked($sender_uuid, $friend_uuid)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("You have blocked the user, unblock to send friend request"));
        return;
    }

    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$friend_uuid/Friends";
    if (!-d $friend_path) {
        mkdir($friend_path) or do {
            http_utils::send_http_response($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
            return;
        };
    }

    my $requests_file = "$friend_path/received_requests.json";
    if (!-e $requests_file) {
        open my $fh, '>', $requests_file or do {
            http_utils::send_http_response($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
            return;
        };
        print $fh "[]";
        close($fh);
    }

    if (are_users_friends($sender_uuid, $friend_uuid)) {
        http_utils::send_http_response($client_socket, HTTP_RESPONSE::ERROR_400("Already friends"));
        return;
    }

    if (has_pending_request($sender_uuid, $friend_uuid)) {
        http_utils::send_http_response($client_socket, HTTP_RESPONSE::ERROR_400("Friend request already sent"));
        return;
    }

    open my $fh, '<', $requests_file;
    my $requests_data = do { local $/; <$fh> };
    close $fh;

    my $requests = decode_json($requests_data);

    my %request = (
        UserId => $sender_uuid,
        TimeSentTimestamp => time()
    );

    push @$requests, \%request;

    open $fh, '>', $requests_file;
    print $fh encode_json($requests);
    close $fh;

    my $sender_path = "$base_dir/Data/UserData/Users/$sender_uuid/Friends";
    if (!-d $sender_path) {
        mkdir($sender_path) or do {
            http_utils::send_http_response($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
            return;
        };
    }

    my $sent_requests_file = "$sender_path/sent_requests.json";
    if (!-e $sent_requests_file) {
        open $fh, '>', $sent_requests_file or do {
            http_utils::send_http_response($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
            return;
        };
        print $fh "[]";
        close($fh);
    }

    open $fh, '<', $sent_requests_file;
    my $sent_requests_data = do { local $/; <$fh> };
    close $fh;

    my $sent_requests = decode_json($sent_requests_data);


    my %sent_request = (
        UserId => $friend_uuid,
        TimeSentTimestamp => time()
    );

    push @$sent_requests, \%sent_request;

    open $fh, '>', $sent_requests_file;
    print $fh encode_json($sent_requests);
    close $fh;

    %request = (
            UserId => $friend_uuid,
            UserName => user_utils::get_username_by_uuid($friend_uuid),
            DisplayName => user_utils::get_displayname_by_uuid($friend_uuid),
            TimeSentTimestamp => $sent_request{TimeSentTimestamp}
    );

    http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK_WITH_DATA(encode_json(\%request), "sent_request.json"));
}

sub get_received_requests {
    my ($client_socket, $path) = @_;

    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$main::user->{uuid}/Friends";
    if (!-d $friend_path) {
        http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK("{}"));
        return;
    }

    my $requests_file = "$friend_path/received_requests.json";
    if (!-e $requests_file) {
        http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK("{}"));
        return;
    }


    open my $fh, '<', $requests_file;
    my $requests_data = do { local $/; <$fh> };
    close $fh;	
    $requests_data = decode_json($requests_data);

    my @requests;
    foreach my $request (@$requests_data) {
        my $uuid = $request->{UserId};
        my %request = (
            UserId => $uuid,
            UserName => user_utils::get_username_by_uuid($uuid),
            DisplayName => user_utils::get_displayname_by_uuid($uuid),
            TimeSentTimestamp => $request->{TimeSentTimestamp}
        );
        push @requests, \%request;
    }

    my $response = HTTP_RESPONSE::OK_WITH_DATA(encode_json(\@requests), "received_requests.json");
    http_utils::send_http_response($client_socket, $response);
}

sub get_sent_requests {
    my ($client_socket, $path) = @_;

    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$main::user->{uuid}/Friends";
    if (!-d $friend_path) {
        http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK("{}"));
        return;
    }

    my $requests_file = "$friend_path/sent_requests.json";
    if (!-e $requests_file) {
        http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK("{}"));
        return;
    }


    open my $fh, '<', $requests_file;
    my $requests_data = do { local $/; <$fh> };
    close $fh;	
    $requests_data = decode_json($requests_data);

    my @requests;
    foreach my $request (@$requests_data) {
        my $uuid = $request->{UserId};
        my %request = (
            UserId => $uuid,
            UserName => user_utils::get_username_by_uuid($uuid),
            DisplayName => user_utils::get_displayname_by_uuid($uuid),
            TimeSentTimestamp => $request->{TimeSentTimestamp}
        );
        push @requests, \%request;
    }

    my $response = HTTP_RESPONSE::OK_WITH_DATA(encode_json(\@requests), "sent_requests.json");
    http_utils::send_http_response($client_socket, $response);
}

sub accept_friend_request {
    my ($client_socket, $route, $temp_file) = @_;

    my $body = body_utils::load_temp_file($temp_file);
    my $json = decode_json($body);
    my $friend_uuid = $json->{userId};
    if (!$friend_uuid) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Invalid Request"));
        return;
    }

    if (!user_utils::user_exists($client_socket, $friend_uuid)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("User not found"));
        return;
    }

    remove_received_friend_request($main::user->{uuid}, $friend_uuid, $client_socket);

    remove_sent_friend_request($friend_uuid, $main::user->{uuid}, $client_socket);

    if (are_users_friends($main::user->{uuid}, $friend_uuid)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Already friends"));
        return;
    }

    my $friend = add_friend($main::user->{uuid}, $friend_uuid, $client_socket);

    add_friend($friend_uuid, $main::user->{uuid}, $client_socket);


    http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK_WITH_DATA(encode_json($friend), "friend.json"));
}

sub cancel_friend_request {
    my ($client_socket, $route, $temp_file) = @_;

    my $body = body_utils::load_temp_file($temp_file);
    my $json = decode_json($body);
    my $friend_uuid = $json->{userId};
    if (!$friend_uuid) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Invalid Request"));
        return;
    }

    if (!user_utils::user_exists($client_socket, $friend_uuid)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("User not found"));
        return;
    }

    remove_sent_friend_request($main::user->{uuid}, $friend_uuid, $client_socket);

    remove_received_friend_request($friend_uuid, $main::user->{uuid}, $client_socket);

    http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK("Friend Request Cancelled"));
}

sub decline_friend_request {
    my ($client_socket, $route, $temp_file) = @_;

    my $body = body_utils::load_temp_file($temp_file);
    my $json = decode_json($body);
    my $friend_uuid = $json->{userId};
    if (!$friend_uuid) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Invalid Request"));
        return;
    }

    if (!user_utils::user_exists($client_socket, $friend_uuid)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("User not found"));
        return;
    }

    remove_sent_friend_request($friend_uuid, $main::user->{uuid}, $client_socket);

    remove_received_friend_request($main::user->{uuid}, $friend_uuid, $client_socket);

    http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK("Friend Request Declined"));
}

sub remove_received_friend_request {
    my ($receiver_uuid, $sender_uuid, $client_socket) = @_;

    my $base_dir = getcwd();
    my $receiver_path = "$base_dir/Data/UserData/Users/$receiver_uuid/Friends";
    if (!-d $receiver_path) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
        return;
    }
    my $requests_file = "$receiver_path/received_requests.json";
    if (!-e $requests_file) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
        return;
    }


    open my $fh, '<', $requests_file;
    my $requests_data = do { local $/; <$fh> };
    close $fh;

    my $requests = decode_json($requests_data);

    my @new_requests;
    my $found = 0;
    foreach my $request (@$requests) {
        if ($request->{UserId} eq $sender_uuid) {
            $found = 1;
        } else {
            push @new_requests, $request;
        }
    }

    if (!$found) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
        return;
    }

    open $fh, '>', $requests_file;

    print $fh encode_json(\@new_requests);
    close $fh;
}

sub remove_sent_friend_request {
    my ($sender_uuid, $receiver_uuid, $client_socket) = @_;

    my $base_dir = getcwd();
    my $sender_path = "$base_dir/Data/UserData/Users/$sender_uuid/Friends";
    if (!-d $sender_path) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
        return;
    }
    my $friend_requests_file = "$sender_path/sent_requests.json";
    if (!-e $friend_requests_file) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
        return;
    }

    open my $fh, '<', $friend_requests_file;
    my $friend_requests_data = do { local $/; <$fh> };
    close $fh;

    my $friend_requests = decode_json($friend_requests_data);

    my @new_friend_requests;

    foreach my $request (@$friend_requests) {
        if ($request->{UserId} ne $receiver_uuid) {
            push @new_friend_requests, $request;
        }
    }

    open $fh, '>', $friend_requests_file;
    print $fh encode_json(\@new_friend_requests);
    close $fh;
}

sub add_friend {
    my ($uuid, $friend_uuid, $client_socket) = @_;

    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$uuid/Friends";
    if (!-d $friend_path) {
        mkdir($friend_path) or do {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
            return;
        };
    }
    my $friends_file = "$friend_path/friends.json";
    if (!-e $friends_file) {
        open my $fh, '>', $friends_file or do {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
            return;
        };
        print $fh "[]";
        close($fh);
    }

    open my $fh, '<', $friends_file;
    my $friends_data = do { local $/; <$fh> };
    close $fh;

    my $friends = decode_json($friends_data);

    my %friend = (
        UserId => $friend_uuid,
        FriendsSinceTimestamp => time()
    );

    push @$friends, \%friend;

    open $fh, '>', $friends_file;
    print $fh encode_json($friends);
    close $fh;

    $friend{UserName} = user_utils::get_username_by_uuid($friend_uuid);
    $friend{DisplayName} = user_utils::get_displayname_by_uuid($friend_uuid);
    my $status = "unknown";
    print("GETTING ONLINE STATUS\n");
    if (exists $epoll::clients{online}{friends}{$uuid}) {
        $status = "online";
    } {
        $status = "offline";
    }
    $friend{Status} = $status;

    return \%friend;
}

sub are_users_friends {
    my ($uuid, $friend_uuid) = @_;

    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$uuid/Friends";
    if (!-d $friend_path) {
        return 0;
    }

    my $friends_file = "$friend_path/friends.json";
    if (!-e $friends_file) {
        return 0;
    }

    open my $fh, '<', $friends_file;
    my $friends_data = do { local $/; <$fh> };
    close $fh;

    my $friends = decode_json($friends_data);

    foreach my $friend (@$friends) {
        if ($friend->{UserId} eq $friend_uuid) {
            return 1;
        }
    }

    return 0;
}

sub has_pending_request {
    my ($uuid, $friend_uuid) = @_;

    my $base_dir = getcwd();
    
    my $friend_path = "$base_dir/Data/UserData/Users/$uuid/Friends";
    if (!-d $friend_path) {
        return 0;
    }

    my $requests_file = "$friend_path/sent_requests.json";
    if (!-e $requests_file) {
        return 0;
    }

    open my $fh, '<', $requests_file;
    my $requests_data = do { local $/; <$fh> };
    close $fh;

    my $requests = decode_json($requests_data);

    foreach my $request (@$requests) {
        if ($request->{UserId} eq $friend_uuid) {
            return 1;
        }
    }

    return 0;
}

sub get_friends {
    my ($client_socket, $uuid) = @_;
    print("GETTING FRIENDS\n");
    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$uuid/Friends";
    if (!-d $friend_path) {
        return "[]";
    }

    my $friends_file = "$friend_path/friends.json";
    if (!-e $friends_file) {
        return "[]";
    }

    open my $fh, '<', $friends_file;
    my $friends_data = do { local $/; <$fh> };
    close $fh;

    my $friends = decode_json($friends_data);

    my @friends;
    foreach my $friend (@$friends) {
        print("FRIEND: $friend\n");
        my $uuid = $friend->{UserId};
        if (!user_utils::user_exists($client_socket, $uuid)) {
            next;
        }

        my $displayname = user_utils::get_displayname_by_uuid($uuid) || "failed to fetch";
        my $username = user_utils::get_username_by_uuid($uuid) || "failed to fetch"; 
        my $friendsince = $friend->{FriendsSinceTimestamp} || 0;
        my $status = "unknown";
        print("GETTING ONLINE STATUS\n");
        if (exists $epoll::clients{online}{$uuid}) {
            $status = "online";
        } {
            $status = "offline";
        }
        my %friend = (
            UserId => $uuid,
            UserName => $username,
            DisplayName => $displayname,
            FriendsSinceTimestamp => $friendsince,
            Status => $status
        );
        push @friends, \%friend;
    }
    print("FRIENDS: ". encode_json(\@friends)."\n");
    return encode_json(\@friends);
}

sub get_blocked_users {
    my ($client_socket, $route) = @_;

    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$main::user->{uuid}/Friends";
    if (!-d $friend_path) {
        http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK("{}"));
        return;
    }

    my $blocked_users_file = "$friend_path/blocked_users.json";
    if (!-e $blocked_users_file) {
        http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK("{}"));
        return;
    }

    open my $fh, '<', $blocked_users_file;
    my $blocked_users_data = do { local $/; <$fh> };
    close $fh;

    my $blocked_users = decode_json($blocked_users_data);

    my @sending_blocked_users;

    foreach my $blocked_user (@$blocked_users) {
        my $uuid = $blocked_user->{UserId};
        if (!user_utils::user_exists($client_socket, $uuid)) {
            next;
        }

        my $displayname = user_utils::get_displayname_by_uuid($uuid) || "failed to fetch";
        my $username = user_utils::get_username_by_uuid($uuid) || "failed to fetch"; 
        my $status = "Unknown";
        my %blocked_user = (
            UserId => $uuid,
            UserName => $username,
            DisplayName => $displayname
        );
        push @sending_blocked_users, \%blocked_user;
    }

    my $response = HTTP_RESPONSE::OK_WITH_DATA(encode_json(\@sending_blocked_users), "blocked_users.json");
    http_utils::send_http_response($client_socket, $response);
}

sub block_user {
    my ($client_socket, $route, $temp_file) = @_;

    my $body = body_utils::load_temp_file($temp_file);
    my $json = decode_json($body);
    my $blocked_uuid = $json->{userId};
    if (!$blocked_uuid) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Invalid Request"));
        return;
    }

    if (!user_utils::user_exists($client_socket, $blocked_uuid)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("User not found"));
        return;
    }

    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$main::user->{uuid}/Friends";
    if (!-d $friend_path) {
        mkdir($friend_path) or do {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
            return;
        };
    }

    my $blocked_users_file = "$friend_path/blocked_users.json";
    if (!-e $blocked_users_file) {
        open my $fh, '>', $blocked_users_file or do {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
            return;
        };
        print $fh "[]";
        close($fh);
    }

    if (has_pending_request($main::user->{uuid}, $blocked_uuid)) {
        remove_sent_friend_request($main::user->{uuid}, $blocked_uuid, $client_socket);
        remove_received_friend_request($blocked_uuid, $main::user->{uuid}, $client_socket);
    }

    if (has_pending_request($blocked_uuid, $main::user->{uuid})) {
        remove_sent_friend_request($blocked_uuid, $main::user->{uuid}, $client_socket);
        remove_received_friend_request($main::user->{uuid}, $blocked_uuid, $client_socket);
    }

    if (are_users_friends($main::user->{uuid}, $blocked_uuid)) {
        remove_friend($main::user->{uuid}, $blocked_uuid, $client_socket);
        remove_friend($blocked_uuid, $main::user->{uuid}, $client_socket);
    }

    if (is_user_blocked($main::user->{uuid}, $blocked_uuid)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Already blocked"));
        return;
    }

    open my $fh, '<', $blocked_users_file;
    my $blocked_users_data = do { local $/; <$fh> };
    close $fh;

    my $blocked_users = decode_json($blocked_users_data);

    my %blocked_user = (
        UserId => $blocked_uuid,
        TimeBlockedTimestamp => time()
    );

    push @$blocked_users, \%blocked_user;

    open $fh, '>', $blocked_users_file;
    print $fh encode_json($blocked_users);
    close $fh;

    my %sent_blocked_user = (
        UserId => $blocked_uuid,
        UserName => user_utils::get_username_by_uuid($blocked_uuid),
        DisplayName => user_utils::get_displayname_by_uuid($blocked_uuid),
    );

    http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK_WITH_DATA(encode_json(\%sent_blocked_user), "blocked_user.json"));
}

sub is_user_blocked {
    my ($uuid, $blocked_uuid) = @_;

    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$uuid/Friends";
    if (!-d $friend_path) {
        return 0;
    }
    my $blocked_users_file = "$friend_path/blocked_users.json";
    if (!-e $blocked_users_file) {
        return 0;
    }

    open my $fh, '<', $blocked_users_file;
    my $blocked_users_data = do { local $/; <$fh> };
    close $fh;

    my $blocked_users = decode_json($blocked_users_data);
    print("BLOKCED UUID: $blocked_uuid\n");
    foreach my $blocked_user (@$blocked_users) {
        print("BLOCKED USER: $blocked_user->{UserId}\n");
        if ($blocked_user->{UserId} eq $blocked_uuid) {
            return 1;
        }
    }

    return 0;
}

sub remove_friends {
    my ($client_socket, $route, $temp_file) = @_;
    my $body = body_utils::load_temp_file($temp_file);
    my $json = decode_json($body);
    my $friend_uuid = $json->{userId};
    if (!$friend_uuid) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Invalid Request"));
        return;
    }

    if (!user_utils::user_exists($client_socket, $friend_uuid)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("User not found"));
        return;
    }

    if (!are_users_friends($main::user->{uuid}, $friend_uuid)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Not friends"));
        return;
    }

    my $removed_friend = remove_friend($main::user->{uuid}, $friend_uuid, $client_socket);
    remove_friend($friend_uuid, $main::user->{uuid}, $client_socket);
    
    http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK_WITH_DATA(encode_json($removed_friend), "removed_friend.json"));
}

sub remove_friend {
    my ($uuid, $friend_uuid, $client_socket) = @_;

    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$uuid/Friends";
    if (!-d $friend_path) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
        return;
    }
    my $friends_file = "$friend_path/friends.json";
    if (!-e $friends_file) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
        return;
    }

    open my $fh, '<', $friends_file;
    my $friends_data = do { local $/; <$fh> };
    close $fh;

    my $friends = decode_json($friends_data);

    my @new_friends;

    my %removed_friend;

    foreach my $friend (@$friends) {
        if ($friend->{UserId} ne $friend_uuid) {
            push @new_friends, $friend;
        } else {
            %removed_friend = %$friend;
            $removed_friend{UserName} = user_utils::get_username_by_uuid($friend_uuid);
            $removed_friend{DisplayName} = user_utils::get_displayname_by_uuid($friend_uuid);
            $removed_friend{Status} = "Unknown";
        }
    }

    open $fh, '>', $friends_file;
    print $fh encode_json(\@new_friends);
    close $fh;

    return \%removed_friend;
}

sub unblock_user {
    my ($client_socket, $route, $temp_file) = @_;

    my $body = body_utils::load_temp_file($temp_file);
    my $json = decode_json($body);
    my $blocked_uuid = $json->{userId};
    if (!$blocked_uuid) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Invalid Request"));
        return;
    }

    if (!user_utils::user_exists($client_socket, $blocked_uuid)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("User not found"));
        return;
    }

    if (!is_user_blocked($main::user->{uuid}, $blocked_uuid)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Not blocked"));
        return;
    }

    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$main::user->{uuid}/Friends";
    if (!-d $friend_path) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
        return;
    }

    my $blocked_users_file = "$friend_path/blocked_users.json";
    if (!-e $blocked_users_file) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
        return;
    }

    open my $fh, '<', $blocked_users_file;
    my $blocked_users_data = do { local $/; <$fh> };
    close $fh;

    my $blocked_users = decode_json($blocked_users_data);

    my @new_blocked_users;

    my $found = 0;
    foreach my $blocked_user (@$blocked_users) {
        if ($blocked_user->{UserId} eq $blocked_uuid) {
            $found = 1;
        } else {
            push @new_blocked_users, $blocked_user;
        }
    }

    if (!$found) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
        return;
    }

    open $fh, '>', $blocked_users_file;
    print $fh encode_json(\@new_blocked_users);
    close $fh;

    http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK("User Unblocked"));
}

sub get_friend {
    my ($friend_uuid) = @_;

    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$friend_uuid/Friends";
    if (!-d $friend_path) {
        return "{}";
    }

    my $friends_file = "$friend_path/friends.json";
    if (!-e $friends_file) {
        return "{}";
    }

    open my $fh, '<', $friends_file;
    my $friends_data = do { local $/; <$fh> };
    close $fh;

    my $friends = decode_json($friends_data);

    foreach my $friend (@$friends) {
        if ($friend->{UserId} eq $main::user->{uuid}) {
            my $status = "offline";
            print("GETTING ONLINE STATUS\n");
            if (exists $epoll::clients{online}{$friend_uuid}) {
                $status = "online";
            }
            my %friend = (
                UserId => $main::user->{uuid},
                UserName => user_utils::get_username_by_uuid($main::user->{uuid}),
                DisplayName => user_utils::get_displayname_by_uuid($main::user->{uuid}),
                FriendsSinceTimestamp => $friend->{FriendsSinceTimestamp},
                Status => $status
            );
            return \%friend;
        }
    }
}

sub get_received_request {
    my ($receiver_uuid) = @_;
    print("GETTING RECEIVED REQUEST\n");
    my $base_dir = getcwd();
    my $friend_path = "$base_dir/Data/UserData/Users/$receiver_uuid/Friends";
    if (!-d $friend_path) {
        return "{}";
    }

    my $requests_file = "$friend_path/received_requests.json";
    if (!-e $requests_file) {
        return "{}";
    }

    open my $fh, '<', $requests_file;
    my $requests_data = do { local $/; <$fh> };
    close $fh;

    my $requests = decode_json($requests_data);

    foreach my $request (@$requests) {
        if ($request->{UserId} eq $main::user->{uuid}) {
            my %request = (
                UserId => $main::user->{uuid},
                UserName => user_utils::get_username_by_uuid($main::user->{uuid}),
                DisplayName => user_utils::get_displayname_by_uuid($main::user->{uuid}),
                TimeSentTimestamp => $request->{TimeSentTimestamp}
            );
            return \%request;
        }
    }
    return "{}";
}
1;