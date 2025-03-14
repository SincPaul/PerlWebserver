package channel_utils;

use strict;
use warnings;

use Cwd;
use JSON;

my %items = (
    "title" => \&update_video_title,
    "description" => \&update_video_description,
    "thumbnail" => \&update_video_thumbnail,
    "channel_icon" => \&update_channel_icon,
    "channel_banner" => \&update_channel_banner,
);

my %channel_items = (
    "channel_icon" => \&update_channel_icon,
    "channel_banner" => \&update_channel_banner,
    "about" => \&update_channel_about,
    "displayname" => \&update_channel_displayname,
);

my %categories = (
    "Videos" => \&update_video,
    "Channel" => \&update_channel,
);

my %categories_server_style = (
    "videos" => "Videos",
    "channel" => "Channel",
);
sub update_channel_item {
    my ($username, $category, $video_id, $update_item, $temp_file, $client_socket) = @_;


    $category = $categories_server_style{$category};
    if (!has_manage_access(user_utils::get_uuid_by_username($username))) {
        return;
    }
    
    if (!$categories{$category}) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Category not found"));
        return;
    }

    $categories{$category}->($username, $video_id, $update_item, $temp_file, $client_socket);
}

sub update_channel {
    my ($username, $video_id, $update_item, $temp_file, $client_socket) = @_;


    if (!$channel_items{$update_item}) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Item not found"));
        return;
    }

    $channel_items{$update_item}->($username, $video_id, $update_item, $temp_file, $client_socket);
}

sub update_channel_displayname {
    my ($username, $video_id, $update_item, $temp_file, $client_socket) = @_;

    my $base_dir = getcwd();
    my $user_file = "$base_dir/Data/UserData/Users/$main::user->{uuid}/$main::user->{uuid}.json";
    if (!-e $user_file) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("User not found"));
        return;
    }


    my $data = body_utils::load_temp_file($temp_file);
    my $json = decode_json($data);
    my $new_displayname = $json->{displayname};
    print("NEW DISPLAYNAME: $new_displayname\n");
    if (user_utils::is_wide($new_displayname)) {
        $new_displayname = user_utils::encode_uri($new_displayname);
    }
    
    
    my $old_displayname = user_utils::get_displayname_by_uuid($main::user->{uuid});

    if (!$new_displayname) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Displayname not provided"));
        return;
    }

    if ($new_displayname eq $old_displayname) {
        return 1;
    }

    my $displayname_file = "$base_dir/Data/UserData/displaynames.json";
    if (!-e $displayname_file) {
        open my $fh, ">", $displayname_file;
        print $fh "{ \"displaynames\": {}, \"uuid_to_displayname\": {} }";
        close $fh;
    }

    open my $fh, "<", $displayname_file;
    $data = do { local $/; <$fh> };
    close $fh;

    $json = decode_json($data);
    my $displaynames = $json->{displaynames};
    my $uuid_to_displayname = $json->{uuid_to_displayname};

    if ($uuid_to_displayname->{$main::user->{uuid}}) {
        if ($displaynames->{$old_displayname}) {
            my $user = $displaynames->{$old_displayname};
            my @keeping_uuids;
            foreach my $uuid (@$user) {
                if ($uuid eq $main::user->{uuid}) {
                    next;
                }
                push @keeping_uuids, $uuid;
            }
            if (@keeping_uuids) {
                $displaynames->{$old_displayname} = \@keeping_uuids;
            } else {
                delete $displaynames->{$old_displayname};
            }
        }
    }

    if ($displaynames->{$new_displayname}) {
        push @{$displaynames->{$new_displayname}}, $main::user->{uuid};
    } else {
        $displaynames->{$new_displayname} = [$main::user->{uuid}];
    }

    $uuid_to_displayname->{$main::user->{uuid}} = $new_displayname;

    open $fh, ">", $displayname_file;
    print $fh encode_json($json);
    close $fh;

    open my $user_data_fh, "<", $user_file;
    $data = do { local $/; <$user_data_fh> };
    close $user_data_fh;
    $json = decode_json($data);
    $json->{displayname} = $new_displayname;
    open $user_data_fh, ">", $user_file;
    print $user_data_fh encode_json($json);
    close $user_data_fh;
}

sub update_channel_about {
    my ($username, $video_id, $update_item, $temp_file, $client_socket) = @_;   


    my $body = body_utils::load_temp_file($temp_file);

    my $json = decode_json($body);

    my $about = $json->{about};

    if (!$about) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("About not provided"));
        return;
    }

    my $base_dir = getcwd();
    my $channel_uuid = user_utils::get_uuid_by_username($username);
    my $channel_path = "$base_dir/Data/UserData/Users/$channel_uuid/Streaming/Channel";
    if (!-d $channel_path) {
        mkdir $channel_path;
    }
    my $about_file = "$channel_path/about.txt";
    open my $fh, ">", $about_file;
    print $fh $about;
    close $fh;

    http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK("About updated"));
}

my %update_video_items = (
    "title" => \&update_video_title,
    "description" => \&update_video_description,
    "thumbnail" => \&update_video_thumbnail,
    "enable" => \&enable_video,
    "disable" => \&disable_video,
    "private" => \&make_video_private,
    "public" => \&make_video_public,
    "delete" => \&delete_video,
);

sub update_video {
    my ($category_folder, $video_id, $update_item, $temp_file, $client_socket) = @_;
    my $video_file = "$category_folder/$video_id";
    if (!-e $video_file) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Video not found"));
        return;
    }

    # print("CLIENT SOCKET: $client_socket\n");

    $update_video_items{$update_item}->($video_file, $temp_file, $client_socket);
}

sub enable_video {
    my ($video_file, $temp_file, $client_socket) = @_;

    my $meta_data_file = "$video_file/metadata.json";
    open my $fh, "<", $meta_data_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    # print("DATA: $data\n");
    my $json = decode_json($data);
    # print("JSON: $json\n");
    open $fh, ">", $meta_data_file;
    $json->{enabled} = 1;
    print $fh encode_json($json);
    close $fh;
}

sub update_video_title {
    my ($video_file, $temp_file, $client_socket) = @_;

    my $data = body_utils::load_temp_file($temp_file);
    my $json = decode_json($data);
    my $new_title = $json->{video_title};
    # print("NEW TITLE: $new_title\n");
    if (!$new_title) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Title not provided"));
        return;
    }
    my $meta_data_file = "$video_file/metadata.json";
    open my $fh, "<", $meta_data_file;
    $data = do { local $/; <$fh> };
    close $fh;
    $json = decode_json($data);
    $json->{title} = $new_title;
    open $fh, ">", $meta_data_file;
    print $fh encode_json($json);
    close $fh;
}

sub update_video_description {
    my ($video_file, $temp_file, $client_socket) = @_;

    my $data = body_utils::load_temp_file($temp_file);
    my $json = decode_json($data);
    my $new_description = $json->{video_description};
    # print("NEW DESCRIPTION: $new_description\n");
    if (!$new_description) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Description not provided"));
        return;
    }
    my $meta_data_file = "$video_file/metadata.json";
    open my $fh, "<", $meta_data_file;
    $data = do { local $/; <$fh> };
    close $fh;
    $json = decode_json($data);
    $json->{description} = $new_description;
    open $fh, ">", $meta_data_file;
    print $fh encode_json($json);
    close $fh;
}

sub disable_video {
    my ($video_file, $temp_file, $client_socket) = @_;

    my $meta_data_file = "$video_file/metadata.json";
    open my $fh, "<", $meta_data_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    # print("DATA: $data\n");
    my $json = decode_json($data);
    # print("JSON: $json\n");
    open $fh, ">", $meta_data_file;
    $json->{enabled} = 0;
    print $fh encode_json($json);
    close $fh;
}

sub make_video_public {
    my ($video_file, $temp_file, $client_socket) = @_;

    my $meta_data_file = "$video_file/metadata.json";
    open my $fh, "<", $meta_data_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    # print("DATA: $data\n");
    my $json = decode_json($data);
    # print("JSON: $json\n");
    open $fh, ">", $meta_data_file;
    $json->{private} = 0;
    print $fh encode_json($json);
    close $fh;
}

sub make_video_private {
    my ($video_file, $temp_file, $client_socket) = @_;

    my $meta_data_file = "$video_file/metadata.json";
    open my $fh, "<", $meta_data_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    # print("DATA: $data\n");
    my $json = decode_json($data);
    # print("JSON: $json\n");
    open $fh, ">", $meta_data_file;
    $json->{private} = 1;
    print $fh encode_json($json);
    close $fh;
}

sub delete_video {
    my ($video_file, $temp_file, $client_socket) = @_;

    my ($channel_uuid) = $video_file =~ /\/Data\/UserData\/Users\/(.*)\/Streaming\/Videos\/(.*)/; 
    my $channel_name = user_utils::get_username_by_uuid($channel_uuid);
    if (!$channel_name) {
        # print("no channel name\n");
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Failed to delete video"));
        return;
    }
    if(!user_utils::delete_files_recursive($video_file)) {
        # print("FAILED TO DELETE VIDEO\n");
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Failed to delete video"));
        return;
    } else {
        remove_from_index($video_file);
        # print("DELETED VIDEO\n");
        # print("CLIENT SOCKET: $client_socket\n");
        # print("HTTP RESPONSE: " . HTTP_RESPONSE::REDIRECT_303("/streaming/manage/channel/$channel_name/videos") . "\n");
        http_utils::send_http_response($client_socket, HTTP_RESPONSE::REDIRECT_303("/streaming/manage/channel/$channel_name/videos"));
        return;
    }
}

sub remove_from_index {
    my ($video_file) = @_;

    my $base_dir = getcwd();
    my ($user_path) = $video_file =~ /(.*)\/Videos/;
    # print("VIDEO FILE: $video_file\n");
    $video_file =~ s/$base_dir\///;
    my $meta_data_file = "$video_file/metadata.json";
    # print("VIDEO FILE: $video_file\n");
    # print("USER PATH: $user_path\n");
    my $index_file = "$user_path/videos.txt";
    my @videos;
    open my $fh, "<", $index_file;
    while (my $line = <$fh>) {
        chomp $line;
        if ($line eq $meta_data_file) {   
            next;
        }
        push @videos, $line;
    }
    close $fh;
    open $fh, ">", $index_file;
    foreach my $video (@videos) {
        print $fh "$video\n";
    }
    close $fh;
}

sub has_manage_access {
    my ($manage_uuid) = @_;

    if (!$main::user) {
        return 0;
    }

    if ($main::user->{uuid} eq $manage_uuid) {
        return 1;
    }

    return 0;
}


my %post_streaming_channel_items = (
    "subscribe" => \&subscribe_to_channel,
    "unsubscribe" => \&unsubscribe_from_channel,
);
sub post_streaming_channel {
    my ($channel_username, $category, $temp_file, $client_socket) = @_;

    if (!$post_streaming_channel_items{$category}) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Category not found"));
        return;
    }

    $post_streaming_channel_items{$category}->($channel_username, $temp_file, $client_socket);
}

sub subscribe_to_channel {
    my ($channel_username, $temp_file, $client_socket) = @_;


    if (is_subscribed($channel_username)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Already subscribed"));
        return;
    }
    my $base_dir = getcwd();
    my $channel_uuid = user_utils::get_uuid_by_username($channel_username);

    my $channel_metadata = get_channel_metadata($channel_uuid);
    if (!$channel_metadata) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Channel not found"));
        return;
    }
    $channel_metadata->{subscriberCount}++;
    open my $fh, ">", "$base_dir/$channel_metadata->{filepath}";
    print $fh encode_json($channel_metadata);
    close $fh;


    my $metadata_file = get_channel_metadata_file($channel_uuid);
    if (!$metadata_file) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Channel not found"));
        return;
    }
    open $fh, "<", $metadata_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    my $json = decode_json($data);
    $json->{subscribedTo} = 1;
    open $fh, ">", $metadata_file;
    print $fh encode_json($json);
    close $fh;

    my $subscribed_to_file = "$base_dir/Data/UserData/Users/$main::user->{uuid}/Streaming/OtherPeopleInfo/subscribed_to.txt";
    if (!-e $subscribed_to_file) {
        open $fh, ">", $subscribed_to_file;
        close $fh;
    }
    open $fh, ">>", $subscribed_to_file;
    print $fh "$channel_uuid\n";
    close $fh;
}

sub unsubscribe_from_channel {
    my ($channel_username, $temp_file, $client_socket) = @_;

    if (!is_subscribed($channel_username)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Not subscribed"));
        return;
    }
    my $base_dir = getcwd();
    my $channel_uuid = user_utils::get_uuid_by_username($channel_username);

    my $channel_metadata = get_channel_metadata($channel_uuid);
    if (!$channel_metadata) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Channel not found"));
        return 0;
    }
    $channel_metadata->{subscriberCount}--;
    open my $fh, ">", "$base_dir/$channel_metadata->{filepath}";
    print $fh encode_json($channel_metadata);
    close $fh;

    my $metadata_file = get_channel_metadata_file($channel_uuid);
    if (!$metadata_file) {
        return;
    }
    open $fh, "<", $metadata_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    my $json = decode_json($data);
    $json->{subscribedTo} = 0;
    open $fh, ">", $metadata_file;
    print $fh encode_json($json);
    close $fh;

    my $subscribed_to_file = "$base_dir/Data/UserData/Users/$main::user->{uuid}/Streaming/OtherPeopleInfo/subscribed_to.txt";
    if (!-e $subscribed_to_file) {
        return;
    }
    open $fh, "<", $subscribed_to_file;
    my $new_file;
    foreach my $line (<$fh>) {
        chomp $line;
        if ($line eq $channel_uuid) {
            next;
        }
        $new_file .= "$line\n";
    }
    close $fh;
    open $fh, ">", $subscribed_to_file;
    print $fh $new_file;
    close $fh;
}

sub is_subscribed {
    my ($channel_username) = @_;

    my $base_dir = getcwd();
    my $uuid = user_utils::get_uuid_by_username($channel_username);
    my $metadata_file = get_channel_metadata_file($uuid);
    if (!$metadata_file) {
        return 0;
    }
    open my $fh, "<", $metadata_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    # print("DATA: $data\n");
    my $json = decode_json($data);
    if ($json->{subscribedTo} == 1) {
        return 1;
    } else {
        return 0;
    }
}

sub get_channel_metadata_file {
    my ($uuid) = @_;

    my $base_dir = getcwd();
    my $user_path = "$base_dir/Data/UserData/Users/$main::user->{uuid}";
    if (!-d $user_path) {
        return 0;
    }
    my $streaming_path = "$user_path/Streaming";
    if (!-d $streaming_path) {
        mkdir $streaming_path;
    }
    my $other_people_info_path = "$streaming_path/OtherPeopleInfo";
    if (!-d $other_people_info_path) {
        mkdir $other_people_info_path;
    }
    my $channel_other_people_info_path = "$other_people_info_path/$uuid";
    if (!-d $channel_other_people_info_path) {
        mkdir $channel_other_people_info_path;
    }
    my $channel_other_people_info_channel_path = "$channel_other_people_info_path/Channel";
    if (!-d $channel_other_people_info_channel_path) {
        mkdir $channel_other_people_info_channel_path;
    }
    my $metadata_file = "$channel_other_people_info_channel_path/metadata.json";
    if (!-e $metadata_file) {
        open my $fh, ">", $metadata_file;
        print $fh "{ \"subscribedTo\": 0 }";
        close $fh;
    }
    return $metadata_file;
}

sub get_channel_video_metadata_file {
    my ($video_id) = @_;

    my $channel_uuid = video_utils::get_video_publisher($video_id);
    my $base_dir = getcwd();
    my $user_path = "$base_dir/Data/UserData/Users/$main::user->{uuid}";
    if (!-d $user_path) {
        return 0;
    }
    my $streaming_path = "$user_path/Streaming";
    if (!-d $streaming_path) {
        mkdir $streaming_path;
    }
    my $other_people_info_path = "$streaming_path/OtherPeopleInfo";
    if (!-d $other_people_info_path) {
        mkdir $other_people_info_path;
    }
    my $channel_other_people_info_path = "$other_people_info_path/$channel_uuid";
    if (!-d $channel_other_people_info_path) {
        mkdir $channel_other_people_info_path;
    }
    my $channel_other_people_info_videos_path = "$channel_other_people_info_path/Videos";
    if (!-d $channel_other_people_info_videos_path) {
        mkdir $channel_other_people_info_videos_path;
    }
    my $video_path = "$channel_other_people_info_videos_path/$video_id";
    if (!-d $video_path) {
        mkdir $video_path;
    }
    my $metadata_file = "$video_path/$video_id.json";
    if (!-e $metadata_file) {
        open my $fh, ">", $metadata_file;
        print $fh "{ \"liked\": 0 }";
        close $fh;
    }
    return $metadata_file;
}

sub get_channel_metadata {
    my ($channel_uuid) = @_;
    my $base_dir = getcwd();
    my $channel_path = "$base_dir/Data/UserData/Users/$channel_uuid/Streaming/Channel";
    if (!-d $channel_path) {
        return 0;
    }
    
    my $metadata_file = "$channel_path/metadata.json";
    if (!-e $metadata_file) {
        return;
    }
    my ($trimmed_filepath) = $metadata_file =~ /$base_dir(.*)/;

    if (!-e $metadata_file) {
        open my $fh, ">", $metadata_file;
        print $fh "{ \"subscriberCount\": 0, \"viewCount\": 0, \"filepath\": \"$trimmed_filepath\" }";
    }

    open my $fh, "<", $metadata_file;
    my $metadata = do { local $/; <$fh> };
    close $fh;

    return decode_json($metadata);
}

my %post_streaming_video_items = (
    "like" => \&like_video,
    "dislike" => \&dislike_video,
    "comment" => \&comment_video,
);

sub post_streaming_video {
    my ($category, $video_id, $temp_file, $client_socket) = @_;


    if (!$post_streaming_video_items{$category}) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Category not found"));
        return;
    }

    $post_streaming_video_items{$category}->($video_id, $temp_file, $client_socket);
}

sub comment_video {
    my ($video_id, $temp_file, $client_socket) = @_;
    print("VIDEO ID: $video_id\n");

    my $data = body_utils::load_temp_file($temp_file);
    my $json = decode_json($data);
    my $comment = $json->{comment};
    if (!$comment) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("no Comment"));
        return;
    }

    my $base_dir = getcwd();
    my $video_metadata = video_utils::get_video_metadata_with_video_id($video_id);
    if (!$video_metadata) {
        die;
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Video not found"));
        return;
    }
    my $video_path = "$base_dir/Data/UserData/Users/$video_metadata->{channel_uuid}/Streaming/Videos/$video_id";
    if (!-d $video_path) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Video not found"));
        return;
    }

    my $comments_path = "$video_path/Comments";
    if (!-d $comments_path) {
        mkdir $comments_path;
    }

    my $comment_file = "$comments_path/comments.json";
    if (!-e $comment_file) {
        open my $fh, ">", $comment_file;
        print $fh "{}";
        close $fh;
    }

    my $comment_id = get_comment_id($comment_file);
    
    open my $fh, "<", $comment_file;
    my $comments = do { local $/; <$fh> };
    close $fh;
    my $comments_json = decode_json($comments);
    my %new_comment = (
        author_uuid => $main::user->{uuid},
        replies => {},
        comment_id => $comment_id,
        likes => 0,
        dislikes => 0,
        comment => $comment,
        commented_at => time,
        video_id => $video_id,
    );

    $comments_json->{$comment_id} = \%new_comment;
    open $fh, ">", $comment_file;
    print $fh encode_json($comments_json);
    close $fh;

    $new_comment{author_displayname} = user_utils::get_displayname_by_uuid($new_comment{author_uuid});
    $new_comment{author_username} = user_utils::get_username_by_uuid($new_comment{author_uuid});
    $new_comment{comment_date} = streaming_html::parse_date($new_comment{commented_at});
    
    http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK_WITH_DATA(encode_json(\%new_comment)));
}

sub get_comment_id {
    my ($comment_file) = @_;

    open my $fh, "<", $comment_file;
    my $comments = do { local $/; <$fh> };
    close $fh;
    my $comments_json = decode_json($comments);
    my $comment_id = 1;
    while ($comments_json->{$comment_id}) {
        $comment_id++;
    }
    return $comment_id;
}

sub like_video {
    my ($video_id, $temp_file, $client_socket) = @_;

    if (is_video_liked($video_id)) {
        if (!remove_like($video_id)) {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Failed to remove like"));
            return;
        }
        return 1;
    }
    if (is_video_disliked($video_id)) {
        if (!remove_dislike($video_id)) {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Failed to remove dislike"));
            return;
        }
    }
    my $metadata_file = get_channel_video_metadata_file($video_id);
    if (!$metadata_file) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Video not found"));
        return;
    }

    if (!add_like($video_id)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Failed to add like"));
        return;
    }

    open my $fh, "<", $metadata_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    my $json = decode_json($data);

    $json->{liked} = 1;
    open $fh, ">", $metadata_file;
    print $fh encode_json($json);
    close $fh;   
}

sub dislike_video {
    my ($video_id, $temp_file, $client_socket) = @_;

    if (is_video_disliked($video_id)) {
        if (!remove_dislike($video_id)) {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Failed to remove dislike"));
            return;
        } 
        return 1;
    }

    if (is_video_liked($video_id)) {
        if (!remove_like($video_id)) {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Failed to remove like"));
            return;
        }
    }
    my $metadata_file = get_channel_video_metadata_file($video_id);
    if (!$metadata_file) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Video not found"));
        return;
    }

    if (!add_dislike($video_id)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Failed to add dislike"));
        return;
    }

    open my $fh, "<", $metadata_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    my $json = decode_json($data);
    $json->{liked} = -1;
    open $fh, ">", $metadata_file;
    print $fh encode_json($json);
    close $fh;
}

sub is_video_liked {
    my ($video_id) = @_;

    my $metadata_file = get_channel_video_metadata_file($video_id);
    if (!$metadata_file) {
        return 0;
    }
    open my $fh, "<", $metadata_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    my $json = decode_json($data);
    if ($json->{liked} == 1) {
        return 1;
    } else {
        return 0;
    }
}

sub is_video_disliked {
    my ($video_id) = @_;

    my $metadata_file = get_channel_video_metadata_file($video_id);
    if (!$metadata_file) {
        return 0;
    }
    open my $fh, "<", $metadata_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    my $json = decode_json($data);
    if ($json->{liked} == -1) {
        return 1;
    } else {
        return 0;
    }
}

sub add_like {
    my ($video_id) = @_;
        

    my $video_metadata = video_utils::get_video_metadata_with_video_id($video_id);
    if (!$video_metadata) {
        return;
    }
    $video_metadata->{likes}++;

    my $base_dir = getcwd();
    print("FILEPATH: $video_metadata->{metadata_filepath}\n");
    open my $fh, ">", "$base_dir/$video_metadata->{metadata_filepath}" or die "Cannot open file: $!";
    print $fh encode_json($video_metadata);
    close $fh;
}

sub remove_like {
    my ($video_id) = @_;

    my $video_metadata = video_utils::get_video_metadata_with_video_id($video_id);
    if (!$video_metadata) {
        return;
    }
    $video_metadata->{likes}--;

    my $base_dir = getcwd();
    open my $fh, ">", "$base_dir/$video_metadata->{metadata_filepath}";
    print $fh encode_json($video_metadata);
    close $fh;

    my $metadata_file = get_channel_video_metadata_file($video_id);
    if (!$metadata_file) {
        return;
    }

    open $fh, "<", $metadata_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    my $json = decode_json($data);

    $json->{liked} = 0;
    open $fh, ">", $metadata_file;
    print $fh encode_json($json);
    close $fh;
}

sub add_dislike {
    my ($video_id) = @_;

    my $video_metadata = video_utils::get_video_metadata_with_video_id($video_id);
    if (!$video_metadata) {
        return;
    }
    $video_metadata->{dislikes}++;

    my $base_dir = getcwd();
    open my $fh, ">", "$base_dir/$video_metadata->{metadata_filepath}";
    print $fh encode_json($video_metadata);
    close $fh;
}

sub remove_dislike {
    my ($video_id) = @_;

    my $video_metadata = video_utils::get_video_metadata_with_video_id($video_id);
    if (!$video_metadata) {
        return;
    }
    $video_metadata->{dislikes}--;

    my $base_dir = getcwd();
    open my $fh, ">", "$base_dir/$video_metadata->{metadata_filepath}";
    print $fh encode_json($video_metadata);
    close $fh;

    my $metadata_file = get_channel_video_metadata_file($video_id);
    if (!$metadata_file) {
        return;
    }

    open $fh, "<", $metadata_file;
    my $data = do { local $/; <$fh> };
    close $fh;
    my $json = decode_json($data);
    $json->{liked} = 0;
    open $fh, ">", $metadata_file;
    print $fh encode_json($json);
    close $fh;
}


1;