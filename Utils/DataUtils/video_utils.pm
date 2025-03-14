package video_utils;

use strict;
use warnings;

use Cwd;
use MIME::Base64;
use Digest::SHA qw(sha256_hex);
use JSON;

sub get_top_videos {
    my ($last_video) = @_;
    if (!$last_video) {
        $last_video = 0;
    }
    my $base_dir = getcwd();
    my $video_path = "$base_dir/Data/Streaming/Videos";
    my $videos_file = "$video_path/videos.txt";
    my @videos = get_videos($videos_file, $last_video);
    # foreach my $video (@videos) {
        # print("VIDEO: $video\n");
    # }
    return @videos;
}

sub get_channel_videos {
    my ($channel_uuid, $last_video) = @_;

    if (!$last_video) {
        $last_video = 0;
    }

    my $base_dir = getcwd();
    my $channel_path = "$base_dir/Data/UserData/Users/$channel_uuid/Streaming";
    my $videos_file = "$channel_path/videos.txt";
    if (!-e $videos_file) {
        die;
    }
    my @videos = get_videos($videos_file, $last_video);
}

sub get_videos {
    my ($videos_file, $last_video) = @_;
    if (!$last_video) {
        $last_video = 0;
    }
    $last_video++;
    my $counter = 1;
    my $videos_amount = 4;

    my $base_dir = getcwd();
    open my $fh, "<", $videos_file or do {
        warn "Could not open file $videos_file: $!";
        return;
    };
    my @videos;
    while (my $line = <$fh>) {
        last if $counter >= $videos_amount + $last_video;
        print("COUNTER: $counter\n");
        if ($counter < $last_video) {
            $counter++;
            next;
        }
        chomp $line;
        my $meta_data_file = "$base_dir/$line";
        
        my $video_data = get_video_metadata($meta_data_file);
        if (!$video_data) {
            $counter++;
            $last_video++;
            next;
        }
        # print("VIDEO DATA: $video_data\n");
        # print("IS ENABLED: $video_data->{enabled}\n");
        if ($video_data->{enabled} && !$video_data->{private}) {
            # print("PUSHING VIDEO: $video_data->{title}\n");
            $video_data->{counter_id} = $counter;
            push(@videos, $video_data);
        } else {
            $counter++;
            $last_video++;
            next;
        }
        $counter++;

    }
    close $fh;

    return @videos;
}

sub get_video_metadata {
    my ($meta_data_file) = @_;

    open my $meta_fh, "<", $meta_data_file or do {
        return;
    };
    my $base_dir = getcwd();
    my $meta_data = do { local $/; <$meta_fh> };
    close $meta_fh;
    if (!$meta_data) {
        return;
    }

    
    my $video = { video_name => $meta_data };
    my $video_data = decode_json($meta_data);
    # print("THUMBNAIL PATH: $video_data->{thumbnail}\n");
    # print("VIDEO DATA: $video_data\n");
    # print("FILE: $file\n");
    print("METADATA: $meta_data\n");
    print("VIDEO DATA: $video_data\n");
    # foreach my $key (keys %$file) {
    #     print("KEY: $key\n");
    #     print("VALUE: $file->{$key}\n");
    # }
        # $video->{filepath} = $file->{filepath};
    my %new_video_data = %$video_data;
    $new_video_data{channel_name} = user_utils::get_displayname_by_uuid($video_data->{channel_uuid});
    $new_video_data{channel_username} = user_utils::get_username_by_uuid($video_data->{channel_uuid});
    $new_video_data{description} = user_utils::decode_uri($video_data->{description});
    $new_video_data{description} =~ s/\+/ /g;


    # print("VIDEO DATA: $new_video_data{title}\n");
        
    return \%new_video_data;
}


sub create_new_video_id {
    my $base_dir = getcwd();
    my $video_path = "$base_dir/Data/Streaming/Videos";
    my $video_id_file = "$video_path/video_id.txt";
    
    open my $fh, "<", $video_id_file;
    my $video_id = <$fh>;
    close $fh;
    
    $video_id++;

    if (!$video_id) {
        $video_id = 1;
    }
    
    my $hash = sha256_hex($video_id);
    my $b64 = encode_base64($hash, "");
    my $encoded_id = substr($b64, 0, 11);
    
    open $fh, ">", $video_id_file;
    print $fh $video_id;
    close $fh;
    
    return $encoded_id;
}

my %video_endings = (
    "mp4" => "video/mp4",
    "webm" => "video/webm",
    "ogg" => "video/ogg"
);

sub get_video {
    my ($video_id, $client_socket) = @_;
    # print("GETTING VIDEO\n");
    my $base_dir = getcwd();
    my $video_path = "$base_dir/Data/Streaming/Videos";
    my $videos_file = "$video_path/videos.txt";
    my $full_file_path;
    open my $fh, "<", $videos_file;
    
    while (my $line = <$fh>) {
        chomp $line;
        if ($line !~ /$video_id/) {
            next;
        }
        my $meta_data_file = "$base_dir/$line";
        open my $meta_fh, "<", $meta_data_file;
        my $meta_data = do { local $/; <$meta_fh> };
        close $meta_fh;
        my $video_data = decode_json($meta_data);
        # print("VIDEO DATA: $video_data\n");
        # foreach my $key (keys %$file) {
            # print("KEY: $key\n");
            # print("VALUE: $file->{$key}\n");
        # }
        if (!$video_data->{enabled} && $main::user->{uuid} ne $video_data->{channel_uuid}) {
            die;
            return HTTP_RESPONSE::ERROR_404("Video not found");
        }
        my $file_path = $video_data->{filepath};
        # print("FILE PATH: $file_path\n");
        $full_file_path = "$base_dir/$file_path";
        # print("Full file path: $full_file_path\n");
        last;
    }
    close $fh;

    if (!$full_file_path) {
        return HTTP_RESPONSE::ERROR_404("Video not found");
    }

    if (!-e $full_file_path) {
        return HTTP_RESPONSE::ERROR_404("Video not found");
    }
    my $file_size = -s $full_file_path;
    # print("FILE SIZE: $file_size\n");
    my $start_range_none = 0;
    my ($start_range, $end_range) = request_utils::get_range($main::header);
    # print("RANGE: $start_range - $end_range\n");
    if ($start_range eq "none") {
        $start_range = 0;
        $start_range_none = 1;
        $end_range = 0;
    }
    
    my $file_ending = $full_file_path;
    $file_ending =~ s/.*\.(.*)/$1/;
    my $content_type = $video_endings{$file_ending};


    if ($start_range eq "0") {
        $start_range = 0;
    }

    if (!$end_range) {
        $end_range = $start_range + 524288;
        # print("END RANGE: $end_range\n");
    }
    
    # print("FULL FILE PATH: $full_file_path\n");
    open my $video_fh, "<", $full_file_path;
    binmode $video_fh;
    if ($start_range) {
        seek($video_fh, $start_range, 0);
    }
    my $video_data = "";
    if ($end_range) {
        # print("SIZE FILE: $file_size\n");
        if ($end_range > $file_size) {
            $end_range = $file_size;
        }
        read($video_fh, $video_data, $end_range - $start_range + 1);
    } else {
        die "No end range";
    }
    close $video_fh;

    if ($start_range_none) {
        http_utils::send_response($client_socket, HTTP_RESPONSE::OK_ACCEPT_RANGE($video_data, $file_size, $content_type));
        return;
    }
    # print("VIDEO DATA: $video_data\n");
    my $partial_content = HTTP_RESPONSE::PARTIAL_CONTENT_206($video_data, $start_range, $end_range, $file_size, $content_type);
    # print("SENDING RESPONSE to $end_range\n");
    http_utils::send_response($client_socket, $partial_content);
}

sub get_video_metadata_with_video_id {
    my ($video_id) = @_;
    # print("VIDEO ID: $video_id\n");
    my $base_dir = getcwd();
    my $video_path = "$base_dir/Data/Streaming/Videos";
    my $videos_file = "$video_path/videos.txt";
    if (!-e $videos_file) {
        return;
    }
    open my $fh, "<", $videos_file;
    my $video_data;
    my $metadata;
    while (my $line = <$fh>) {
        chomp $line;
        if ($line !~ /$video_id/) {
            next;
        }
        my $meta_data_file = "$base_dir/$line";
        print("META DATA FILE: $meta_data_file\n");
        $metadata = get_video_metadata($meta_data_file);
        last;
    }
    return $metadata
}

sub get_video_publisher {
    my ($video_id) = @_;
    
    my $video_metadata = get_video_metadata_with_video_id($video_id);
    if (!$video_metadata) {
        return;
    }
    my $channel_uuid = $video_metadata->{channel_uuid};
    return $channel_uuid;
}


sub create_video_emblem {
    my ($video) = @_;

    my $video_id = $video->{video_id};
    my $counter_id = $video->{counter_id};
    my $video_title = user_utils::decode_uri($video->{title});
    my $base_dir = getcwd();
    my $thumbnail_path = "$base_dir/$video->{thumbnail}";
    my $channel_name = user_utils::decode_uri($video->{channel_name}) || "Cant fetch Channel";
    my $channel_username = $video->{channel_username};
    my $channel_uuid = $video->{channel_uuid};
    my $html .= <<HTML;
                        <div class="Video" id="video_$counter_id">
                            <button type="button" class="Thumbnail" onclick="window.location.href='/streaming/watch/v=$video_id'">
                                <img src="/streaming/image/src/$video_id" alt="Video Thumbnail: $video_title">
                            </button>
                            <div class="VideoMetadata">
                                <button type="button" class="ChannelIcon" onclick="window.location.href='/streaming/channel/$channel_username'">
                                    <img src="/streaming/image/channel_icon/$channel_uuid" alt="Channel Icon">
                                </button>
                                <div class="OtherMetadata">
                                    <div class="VideoTitle">
                                        <a href="/streaming/watch/v=$video_id" title="$video_title">$video_title</a>
                                    </div>
                                    <div class="ChannelName">
                                        <a href="/streaming/channel/$channel_username">$channel_name</a>
                                    </div>
                                    <div class="VideoInline">
                                        <div class="VideoViews">
                                            $video->{views} views
                                        </div>
                                        <div class="VideoSeparator">
                                            •
                                        </div>
                                        <div class="VideoUploadDate">
                                            @{[timeAgo($video->{uploaded_at})]} ago
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
HTML

    return $html;
}

sub timeAgo {
    my ($time) = @_;
    my $now = time();
    my $diff = $now - $time;
    
    if ($diff < 60) {
        return "$diff seconds";
    } elsif ($diff < 3600) {
        return int($diff / 60) . " minutes";
    } elsif ($diff < 86400) {
        return int($diff / 3600) . " hours";
    } else {
        return int($diff / 86400) . " days";
    }
}

sub get_private_video_stats {
    my ($video_id) = @_;

    my $video_stats_file = channel_utils::get_channel_video_metadata_file($video_id);

    open my $fh, "<", $video_stats_file;
    my $video_stats = do { local $/; <$fh> };
    close $fh;

    my $video_stats_json = decode_json($video_stats);
    
    return $video_stats_json;
}

sub add_view {
    my ($video_id) = @_;

    if (is_user_in_timeout($main::user->{uuid}, $video_id)) {
        return;
    }

    if (!increase_view_count($video_id)) {
        return;
    }

    add_user_to_timeout($main::user->{uuid}, $video_id);
}

sub is_user_in_timeout {
    my ($uuid, $video_id) = @_;
    my $timeout_time = 60*60*6; # 6h

    my $base_dir = getcwd();
    my $timeout_file = "$base_dir/Data/Streaming/Videos/Timeouts/$video_id/timeouts.json";
    if (!-e $timeout_file) {
        return 0;
    }
    open my $fh, "<", $timeout_file or die;
    my $data = do { local $/; <$fh> };
    close $fh;

    my $json = decode_json($data);

    if (!$json->{$uuid}) {
        return 0;
    }

    my $timeout_timestamp = $json->{$uuid};
    my $now_time = time();

    if ($timeout_timestamp + $timeout_time < $now_time) {
        return 0;
    }

    return 1;
}

sub increase_view_count {
    my ($video_id) = @_;

    my $video_metadata = get_video_metadata_with_video_id($video_id);
    if (!$video_metadata) {
        return 0;
    }

    $video_metadata->{views}++;

    my $base_dir = getcwd();
    open my $fh, '>', "$base_dir/$video_metadata->{metadata_filepath}" or die;
    print $fh encode_json($video_metadata);
    close $fh;
}
# $base_dir/Data/Streaming/Videos/Timeouts/$video_id/timeouts.json"
sub add_user_to_timeout {
    my ($uuid, $video_id) = @_;

    my $base_dir = getcwd();
    my $videos_path = "$base_dir/Data/Streaming/Videos";
    if (!-d $videos_path) {
        return;
    }

    my $timeout_path = "$videos_path/Timeouts";
    if (!-d $timeout_path) {
        mkdir $timeout_path or die ":$!";
    }
    my $video_timeout_path = "$timeout_path/$video_id";
    if (!-d $video_timeout_path) {
        mkdir $video_timeout_path;
    }

    my $video_timeout_metadata_file = "$video_timeout_path/timeouts.json";
    if (!-e $video_timeout_metadata_file) {
        open my $fh, '>', $video_timeout_metadata_file;
        print $fh "{}";
        close $fh;
    }

    open my $fh, '<', $video_timeout_metadata_file or die "$!";
    my $data = do { local $/; <$fh> };
    close $fh;

    my $json = decode_json($data);
    $json->{$uuid} = time();

    open $fh, '>', $video_timeout_metadata_file or die;
    print $fh encode_json($json);
    close $fh;
}

sub get_comments {
    my ($video_id, $last_comment) = @_;
    if (!$last_comment) {
        $last_comment = 0;
    }
    $last_comment++;
    my $channel_uuid = get_video_publisher($video_id);
    my $base_dir = getcwd();

    my $comments_file = "$base_dir/Data/UserData/Users/$channel_uuid/Streaming/Videos/$video_id/Comments/comments.json";
    if (!-e $comments_file) {
        return;
    }

    open my $fh, "<", $comments_file or die;
    my $data = do { local $/; <$fh> };
    close $fh;

    my $json = decode_json($data);

    my @comments;
    my $counter = 0;
    my $comments_amount = 4;
    for (my $comment_id = $last_comment; $comment_id <= scalar(keys %$json) && $counter < $comments_amount; $comment_id++) {
        last if $counter >= $comments_amount + $last_comment;
        if ($json->{$comment_id}->{deleted}) {
            $counter++;
            next;
        }
        if (!$json->{$comment_id}) {
            $counter++;
            next;
        }
        my $comment = $json->{$comment_id};
        push(@comments, $comment);
        $counter++;
    }

    return \@comments;
}

my %video_comment_items = (
    "reply" => \&reply_to_comment,
    "like" => \&like_comment,
    "dislike" => \&dislike_comment,
);

sub manage_video_comments {
    my ($category, $video_id, $parent_comment_id, $temp_file, $client_socket) = @_;

    if (!$main::user) {
        return;
    }

    if (!$video_comment_items{$category}) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Not found"));
        return;
    }

    $video_comment_items{$category}->($video_id, $parent_comment_id, $temp_file, $client_socket);
}

sub get_comment_liked_status {
    my ($video_id, $comment_id, $parent_comment_id) = @_;

    my $comment_state_file = get_comment_state_file($video_id, $comment_id, $parent_comment_id);
    if (!$comment_state_file) {
        return;
    }
    open my $fh, "<", $comment_state_file or die;
    my $data = do { local $/; <$fh> };
    close $fh;

    my $json = decode_json($data);
    return $json->{liked};
}

sub like_comment {
    my ($video_id, $comment_id, $temp_file, $client_socket, $parent_comment_id) = @_;

    if (is_comment_liked($video_id, $comment_id, $parent_comment_id)) {
        if (!remove_comment_like($video_id, $comment_id, $parent_comment_id)) {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
            return;
        }
        return 1;
    }

    if (is_comment_disliked($video_id, $comment_id, $parent_comment_id)) {
        if (!remove_comment_dislike($video_id, $comment_id, $parent_comment_id)) {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
            return;
        }
    }

    if (!add_comment_like($video_id, $comment_id, $parent_comment_id)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error"));
        return;
    }

    return 1;
}

sub dislike_comment {
    my ($video_id, $comment_id, $temp_file, $client_socket, $parent_comment_id) = @_;
    if (is_comment_disliked($video_id, $comment_id, $parent_comment_id)) {
        if (!remove_comment_dislike($video_id, $comment_id, $parent_comment_id)) {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error1"));
            return;
        }
        return 1;
    }

    if (is_comment_liked($video_id, $comment_id, $parent_comment_id)) {
        if (!remove_comment_like($video_id, $comment_id, $parent_comment_id)) {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error2"));
            return;
        }
    }

    if (!add_comment_dislike($video_id, $comment_id, $parent_comment_id)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal Server Error3"));
        return;
    }

    return 1;
}

sub is_comment_liked {
    my ($video_id, $comment_id, $parent_comment_id) = @_;

    my $comment_state_file = get_comment_state_file($video_id, $comment_id, $parent_comment_id);
    if (!$comment_state_file) {
        return 0;
    }

    open my $fh, "<", $comment_state_file or die "$!";
    my $data = do { local $/; <$fh> };
    close $fh;

    my $json = decode_json($data);

    if ($json->{liked} == 1) {
        return 1;
    }

    return 0;
}

sub remove_comment_like {
    my ($video_id, $comment_id, $parent_comment_id) = @_;

    my $comment_state_file = get_comment_state_file($video_id, $comment_id, $parent_comment_id);
    if (!$comment_state_file) {
        return;
    }

    open my $fh, "<", $comment_state_file or die;
    my $data = do { local $/; <$fh> };
    close $fh;

    my $json = decode_json($data);

    $json->{liked} = 0;

    open $fh, ">", $comment_state_file or die;
    print $fh encode_json($json);
    close $fh;

    my $channel_uuid = get_video_publisher($video_id);
    my $base_dir = getcwd();
    my $comments_file = "$base_dir/Data/UserData/Users/$channel_uuid/Streaming/Videos/$video_id/Comments/comments.json";
    if (!-e $comments_file) {
        return;
    }

    open $fh, "<", $comments_file or die;
    $data = do { local $/; <$fh> };
    close $fh;

    $json = decode_json($data);

    my $comment;
    if ($parent_comment_id) {
        $comment = $json->{$parent_comment_id}->{replies}->{comment_id};
    } else {
        $comment = $json->{$comment_id};
    }
    if (!$comment) {
        return;
    }

    $comment->{likes}--;

    open $fh, ">", $comments_file or die;
    print $fh encode_json($json);
    close $fh;
}

sub add_comment_like {
    my ($video_id, $comment_id, $parent_comment_id) = @_;

    my $comment_state_file = get_comment_state_file($video_id, $comment_id, $parent_comment_id);
    if (!$comment_state_file) {
        return;
    }
    print("EXISTING FILE: $comment_state_file\n");

    open my $fh, "<", $comment_state_file or die;
    my $data = do { local $/; <$fh> };
    close $fh;

    my $json = decode_json($data);

    $json->{liked} = 1;

    open $fh, ">", $comment_state_file or die;
    print $fh encode_json($json);
    close $fh;

    my $channel_uuid = get_video_publisher($video_id);
    my $base_dir = getcwd();
    my $comments_file = "$base_dir/Data/UserData/Users/$channel_uuid/Streaming/Videos/$video_id/Comments/comments.json";
    if (!-e $comments_file) {
        return;
    }

    open $fh, "<", $comments_file or die;
    $data = do { local $/; <$fh> };
    close $fh;

    $json = decode_json($data);

    my $comment;
    if ($parent_comment_id) {
        $comment = $json->{$parent_comment_id}->{replies}->{$comment_id};
    } else {
        $comment = $json->{$comment_id};
    }

    if (!$comment) {
        return;
    }

    $comment->{likes}++;

    open $fh, ">", $comments_file or die;
    print $fh encode_json($json);
    close $fh;
}

sub add_comment_dislike {
    my ($video_id, $comment_id, $parent_comment_id) = @_;

    my $comment_state_file = get_comment_state_file($video_id, $comment_id, $parent_comment_id);
    if (!$comment_state_file) {
        return;
    }

    open my $fh, "<", $comment_state_file or die;
    my $data = do { local $/; <$fh> };
    close $fh;

    my $json = decode_json($data);

    $json->{liked} = -1;

    open $fh, ">", $comment_state_file or die;
    print $fh encode_json($json);
    close $fh;

    my $channel_uuid = get_video_publisher($video_id);
    my $base_dir = getcwd();
    my $comments_file = "$base_dir/Data/UserData/Users/$channel_uuid/Streaming/Videos/$video_id/Comments/comments.json";
    if (!-e $comments_file) {
        return;
    }

    open $fh, "<", $comments_file or die;
    $data = do { local $/; <$fh> };
    close $fh;

    $json = decode_json($data);

    my $comment;
    if ($parent_comment_id) {
        $comment = $json->{$parent_comment_id}->{replies}->{comment_id};
    } else {
        $comment = $json->{$comment_id};
    }
    if (!$comment) {
        return;
    }

    $comment->{dislikes}++;

    open $fh, ">", $comments_file or die;
    print $fh encode_json($json);
    close $fh;
}

sub remove_comment_dislike {
    my ($video_id, $comment_id, $parent_comment_id) = @_;

    my $comment_state_file = get_comment_state_file($video_id, $comment_id, $parent_comment_id);
    if (!$comment_state_file) {
        return;
    }

    open my $fh, "<", $comment_state_file or die;
    my $data = do { local $/; <$fh> };
    close $fh;

    my $json = decode_json($data);

    $json->{liked} = 0;

    open $fh, ">", $comment_state_file or die;
    print $fh encode_json($json);
    close $fh;

    my $channel_uuid = get_video_publisher($video_id);
    my $base_dir = getcwd();
    my $comments_file = "$base_dir/Data/UserData/Users/$channel_uuid/Streaming/Videos/$video_id/Comments/comments.json";
    if (!-e $comments_file) {
        return;
    }

    open $fh, "<", $comments_file or die;
    $data = do { local $/; <$fh> };
    close $fh;

    $json = decode_json($data);

    my $comment;
    if ($parent_comment_id) {
        $comment = $json->{$parent_comment_id}->{replies}->{comment_id};
    } else {
        $comment = $json->{$comment_id};
    }
    if (!$comment) {
        return;
    }

    $comment->{dislikes}--;

    open $fh, ">", $comments_file or die;
    print $fh encode_json($json);
    close $fh;
}

sub is_comment_disliked {
    my ($video_id, $comment_id, $parent_comment_id) = @_;

    my $comment_state_file = get_comment_state_file($video_id, $comment_id, $parent_comment_id);
    if (!$comment_state_file) {
        return;
    }

    open my $fh, "<", $comment_state_file or die;
    my $data = do { local $/; <$fh> };
    close $fh;

    my $json = decode_json($data);

    if ($json->{liked} == -1) {
        return 1;
    }

    return 0;
}

sub get_comment_state_file {
    my ($video_id, $comment_id, $parent_comment_id) = @_;

    if (!$main::user) {
        return;
    }
    my $base_dir = getcwd();
    my $user_path = "$base_dir/Data/UserData/Users/$main::user->{uuid}";
    if (!-d $user_path) {
        return;
    }

    my $streaming_path = "$user_path/Streaming";
    if (!-d $streaming_path) {
        mkdir $streaming_path;
    }

    my $other_people_info_path = "$streaming_path/OtherPeopleInfo";
    if (!-d $other_people_info_path) {
        mkdir $other_people_info_path;
    }

    my $channel_uuid = get_video_publisher($video_id);

    my $user_other_people_info_path = "$other_people_info_path/$channel_uuid";
    if (!-d $user_other_people_info_path) {
        mkdir $user_other_people_info_path;
    }
    my $videos_path = "$user_other_people_info_path/Videos";
    if (!-d $videos_path) {
        mkdir $videos_path;
    }
    my $video_path = "$videos_path/$video_id";
    if (!-d $video_path) {
        mkdir $video_path;
    }
    my $comment_path = "$video_path/Comments";
    if (!-d $comment_path) {
        mkdir $comment_path;
    }
    my $file_name;
    if ($parent_comment_id) {
        $file_name = "$parent_comment_id-$comment_id.json";
    } else {
        $file_name = "$comment_id.json";
    }

    my $comment_state_file = "$comment_path/$file_name";
    if (!-e $comment_state_file) {
        print("DOESNT EXIST\n");
        open my $fh, ">", $comment_state_file or die "$! $comment_state_file";
        print $fh "{ \"liked\": 0 }";
        close $fh;
    }

    return $comment_state_file;
}

sub reply_to_comment {
    my ($video_id, $parent_comment_id, $temp_file, $client_socket) = @_;

    my $channel_uuid = get_video_publisher($video_id);
    my $base_dir = getcwd();

    my $comments_file = "$base_dir/Data/UserData/Users/$channel_uuid/Streaming/Videos/$video_id/Comments/comments.json";
    if (!-e $comments_file) {
        return;
    }

    open my $fh, "<", $comments_file or die;
    my $data = do { local $/; <$fh> };
    close $fh;

    my $json = decode_json($data);

    my $reply_data = body_utils::load_temp_file($temp_file);
    my $reply_json = decode_json($reply_data);
    my $reply_comment_text = $reply_json->{reply};
    # print("REPLY DATA: $reply_data\n");
    # print("REPLY JSON: $reply_json\n");
    # print("REPLY COMMENT TEXT: $reply_comment_text\n");
    my $parent_comment = $json->{$parent_comment_id};
    if (!$parent_comment) {
        return;
    }

    my $replies = $parent_comment->{replies};
    if (!$replies) {
        $replies = {};
    }

    my $reply_id = scalar(keys %$replies) + 1;
    my %reply = (
        author_uuid => $main::user->{uuid},
        comment => $reply_comment_text,
        commented_at => time(),
        deleted => 0,
        likes => 0,
        dislikes => 0,
        comment_id => $reply_id,
        video_id => $video_id,
    );


    $replies->{$reply_id} = \%reply;

    open $fh, ">", $comments_file or die;
    print $fh encode_json($json);
    close $fh;

    $reply{author_username} = user_utils::get_username_by_uuid($reply{author_uuid});
    $reply{author_displayname} = user_utils::get_displayname_by_uuid($reply{author_uuid});
    $reply{comment_date} = streaming_html::parse_date($reply{commented_at});
    if ($parent_comment_id) {
        $reply{parent_comment_id} = $parent_comment_id;
    }

    http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK_WITH_DATA(encode_json(\%reply)));
}

my %video_reply_items = (
    "like" => \&like_comment,
    "dislike" => \&dislike_comment,
);

sub manage_video_replies {
    my ($category, $video_id, $parent_comment_id, $comment_id, $temp_file, $client_socket) = @_;

    if (!$main::user) {
        return;
    }

    if (!$video_reply_items{$category}) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Not found"));
        return;
    }

    $video_reply_items{$category}->($video_id, $comment_id, $temp_file, $client_socket, $parent_comment_id);
}

sub parse_mentions {
    my ($comment) = @_;

    print("COMMENT: $comment\n");
    # foreach ($comment =~ /(<span\b(?=[^>]*\bdata-uuid\s*=\s*["']([^"']+)["'])[^>]*>)(.*?)(<\/span>)/g) {
    #     my $uuid = $2;
    #     my $displayname = user_utils::get_displayname_by_uuid($uuid);
    #     $displayname = "\@$displayname";
    #     my $full_match = $1 . $3 . $4;
    #     my $replacement = $1 .$displayname . $4;
        
    #     $comment =~ s/\Q$full_match\E/$replacement/;
    # }
    # ? absolut kein plan was da abgeht, frag mich nicht, frag deepseek
    $comment =~ s/(<span\b(?=[^>]*\bdata-uuid\s*=\s*["']([^"']+)["'])[^>]*>)(.*?)(<\/span>)/ 
        my ($opening, $uuid, $content, $closing) = ($1, $2, $3, $4);
        my $displayname = user_utils::get_displayname_by_uuid($uuid);
        $displayname = "\@$displayname";
        "$opening$displayname$closing";
    /xge;

    return $comment;
}
1;