package upload_utils;

use strict;
use warnings;
use Cwd;
use JSON;
use File::Copy;

my %locations = (
    "streaming/upload" => \&create_streaming_path,
    "/profile/ploud/upload" => \&create_ploud_path,
    "/update/streaming/manage/channel" => \&create_streaming_update_path,
    "/admin/gamelauncher/add" => \&create_game_launcher_path,
);

my %upload_name_list = (
    "title" => "metadata",
    "description" => "metadata",
    "version" => "metadata",
    "game_name" => "metadata",
    "thumbnail" => "thumbnail"
);

my $client; 
my $save_length = 50;

sub handle_upload {
    my ($client_fd) = @_;

    $client = $epoll::clients{$client_fd};
    my $content_length = $epoll::clients{$client_fd}{content_length};

    if ($epoll::clients{$client_fd}{error}) {
        die "Error";
        return;
    }

    if (!$epoll::clients{$client_fd}{finished_metadata} && !$epoll::clients{$client_fd}{error}) {
        my $boundary = $client->{boundary};
        $save_length = length($boundary) + 8;
        # print("GETTING METADATA\n");
        get_metadata($client_fd);
        $epoll::clients{$client_fd}{write_file} = $epoll::clients{$client_fd}{filepath};
    }

    if ($epoll::clients{$client_fd}{finished_metadata} && !$epoll::clients{$client_fd}{finished} && !$epoll::clients{$client_fd}{error}) {
        # print("WRITING FILE\n");
        write_file_until_boundary($client_fd);
    }

    if ($epoll::clients{$client_fd}{finished}) {
        if (!$epoll::clients{$client_fd}{update}) {
            # print("FINISHED UPLOAD 1\n");
            create_meta_data($client_fd);
        } else {
            if ($epoll::clients{$client_fd}{is_icon}) {
                my ($width, $height) = image_utils::get_image_dimensions($epoll::clients{$client_fd}{filepath});
                if ($width != 40 || $height != 40) {
                    restore_old_icon();
                    http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_400("Icon must be 40x40"));
                    return;
                }
            }
            # print("FINISHED UPDATE 2\n");
        }
        my $referer = $epoll::clients{$client_fd}{referer};
        # print("REFERER: $referer\n");
        if (!$referer) {
            $referer = "/";
        }
        my $response = HTTP_RESPONSE::REDIRECT_303($referer);
        # print("RESPOSE: $response\n");
        http_utils::send_http_response($epoll::clients{$client_fd}{socket}, $response);
    }
}

sub restore_old_icon {
    my $base_dir = getcwd;
    my $icon_file = "$base_dir/Data/UserData/Users/$main::user->{uuid}/Streaming/Channel/Icon/channel_icon.json";
    if (!-e $icon_file) {
        return;
    }

    open my $fh, '<', $icon_file or die "Cannot open file: $!";
    my $data = do { local $/; <$fh> };
    close $fh;
    my $icon_data = decode_json($data);
    my $old_icon = $icon_data->{old_icons}->[$#{$icon_data->{old_icons}}];
    my $current_icon = $icon_data->{icon};
    remove_icon($current_icon);
    $icon_data->{icon} = $old_icon;
    pop @{$icon_data->{old_icons}};
    open my $icon_fh, '>', $icon_file or die "Cannot open file: $!";
    print $icon_fh encode_json($icon_data);
    close $icon_fh;    
}

sub remove_icon {
    my ($icon) = @_;

    my $base_dir = getcwd;
    my $icon_path = "$base_dir/$icon";
    if (-e $icon_path) {
        unlink $icon_path or die "Cannot delete file: $!";
    }
}

sub look_for_extra_data {
    my ($client_fd) = @_;
    # print("LOOoking eXtra data\n");

    my $bytes_read = sysread($epoll::clients{$client_fd}{socket}, my $buffer, 1024);
    if ($bytes_read == 0) {
        # print("NO BYTES READ\n");
        return;
    }
    
    if ($buffer =~ /--$epoll::clients{$client_fd}{boundary}--/) {
        $epoll::clients{$client_fd}{complete_finished} = 1;
        return;
    }
}

sub create_meta_data {
    my ($client_fd) = @_;

    my $filename = $epoll::clients{$client_fd}{filename};
    my $content_type = $epoll::clients{$client_fd}{content_type};
    my $name = $epoll::clients{$client_fd}{name};

    my $file_path = $epoll::clients{$client_fd}{filepath};
    my $dir_path = $epoll::clients{$client_fd}{dir_path};
    # print("DIR PATH: $dir_path\n");
    my $filepath = "$dir_path/metadata.json";
    my $base_dir = getcwd;
    my ($trimmed_filepath) = $file_path =~ /$base_dir\/(.*)/; 
    my ($trimmed_metadata_filepath) = $filepath =~ /$base_dir\/(.*)/;

    my %meta_data = (
        filename => $filename,
        filepath => $trimmed_filepath,
        metadata_filepath => $trimmed_metadata_filepath,
        uploaded_at => time(),
        content_type => $content_type,
        size => -s $file_path
    );

    print("MAIN USER: $main::user->{uuid}\n");

    if ($epoll::clients{$client_fd}{video}) {
        $meta_data{enabled} = 1;
        $meta_data{views} = 0;
        $meta_data{likes} = 0;
        $meta_data{dislikes} = 0;
        $meta_data{video_id} = $epoll::clients{$client_fd}{video_id};
        $meta_data{channel_uuid} = $main::user->{uuid};

        my $base_dir = getcwd;
        my $streaming_path = "$base_dir/Data/Streaming";
        if (!-d $streaming_path) {
            mkdir $streaming_path or die "Cannot create directory: $!";
        }
        my $video_path = "$streaming_path/Videos";
        if (!-d $video_path) {
            mkdir $video_path or die "Cannot create directory: $!";
        }
        my $videos_file = "$video_path/videos.txt";
        # print("VIDEOS FILE: $videos_file\n");
        my ($trimmed_filepath) = $filepath =~ /$base_dir\/(.*)/;
        open my $fh, '>>', $videos_file or die "Cannot open file: $!";
        binmode $fh; 
        print $fh "$trimmed_filepath\n";
        close $fh;

        my $user_path = "$base_dir/Data/UserData/Users/$main::user->{uuid}";
        if (!-d $user_path) {
            return;
        }
        my $user_videos_file = "$user_path/Streaming/videos.txt";
        # print("USER VIDEOS FILE: $user_videos_file\n");
        open my $user_fh, '>>', $user_videos_file or die "Cannot open file: $!";
        print($user_fh "$trimmed_filepath\n");
        close $user_fh;
    }

    my $skip;
    my $upload_meta_data_file = "/tmp/upload_meta_data_$client_fd";
    open my $meta_fh, '<', $upload_meta_data_file or do 
    {
        $skip = 1;
    };
    if (!$skip) {
        binmode $meta_fh;
        local $/;
        my %upload_meta_data = %{ decode_json(<$meta_fh>) };
        close $meta_fh;
        foreach my $key (keys %upload_meta_data) {
            $meta_data{$key} = $upload_meta_data{$key};
            if ($key eq "force_new_version") {
                if ($meta_data{$key} eq "true") {
                    $meta_data{$key} = \JSON::true;
                } else {
                    $meta_data{$key} = \JSON::false;
                }
            }
        }
    }

    if (!$epoll::clients{$client_fd}{video} && !$epoll::clients{$client_fd}{game}) {
        user_utils::update_user_metadata($main::user->{uuid}, \%meta_data);
    }

    if ($epoll::clients{$client_fd}{game}) {
        my $version = $meta_data{version};
        if ($version) {
            my $version_path = "$dir_path/$version";
            if (-d $version_path) {
                http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_409("Version already exists"));
                return;
            }
            mkdir $version_path or die "Cannot create directory: $!";
            $filepath = "$dir_path/$version/metadata.json";
            my ($trimmed_filepath) = $filepath =~ /$base_dir\/(.*)/; 
            $meta_data{metadata_filepath} = $trimmed_filepath;

            $file_path = "$dir_path/$version/$filename";
            my ($trimmed_file_path) = $file_path =~ /$base_dir\/(.*)/;
            $meta_data{filepath} = $trimmed_file_path;

            my $game_id = $epoll::clients{$client_fd}{game_id};
            print "Type3: " . (0 + $game_id eq $game_id ? "Integer" : "String") . "\n";
            $meta_data{id} = $game_id;
            my $new_game_id = $meta_data{id};
            print "Type4: " . (0 + $new_game_id eq $new_game_id ? "Integer" : "String") . "\n";

            my $game_name = $meta_data{game_name};
            print("GAME NAME: $game_name\n");
            
            move($epoll::clients{$client_fd}{filepath}, $file_path);

            my $file_hash = user_utils::create_file_hash("sha256", $file_path);
            $meta_data{hash} = $file_hash;

            my $force_new_version = $meta_data{force_new_version};

            print("HASH: $file_hash\n");
            csharp_game::add_to_gamelist($game_id, $game_name);
            csharp_game::update_game_metadata($game_id, $game_name, $version, $file_hash, $force_new_version);
        } else {
            http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_400("Version not defined"));
            return;
        }
    }

    open my $fh, '>', $filepath or die "Cannot open file: $!";
    binmode $fh; 
    print $fh encode_json(\%meta_data);
    close $fh;
}

# sub get_metadata {
#     my ($client_fd) = @_;

#     # print("GETTING METADATA\n");
#     if (!$epoll::clients{$client_fd}{upload_tries} > 3) {
#         # ! KILL CONNECTION
#         die "Too many tries";
#     }
#     if (!$epoll::clients{$client_fd}{read_temp_file}) {
#         print("READING TEMP FILE\n");
#         print($epoll::clients{$client_fd}{temp_file});
#         my $data = body_utils::load_temp_file($epoll::clients{$client_fd}{temp_file});
#         print("DATA: $data\n");
#         $epoll::clients{$client_fd}{read_temp_file} = 1;
#         if ($data =~ /\r\n\r\n/) {
#             my ($metadata, $file_data) = split(/\r\n\r\n/, $data, 2);
#             print("METADATA FOUND: $metadata\n");
#             print("FILE DATA: $file_data\n");
#             # print("DATA123: $file_data\n");
#             extract_metadata($metadata, $client_fd, $file_data);
#             $epoll::clients{$client_fd}{finished_metadata} = 1;
#         } else {
#             return;
#         }
#     } else {
#         my $data = body_utils::load_temp_file($epoll::clients{$client_fd}{temp_file});
#         my $bytes_read = sysread($epoll::clients{$client_fd}{socket}, my $buffer, 1024);
#         $data .= $buffer;
#         if ($bytes_read == 0) {
#             return;
#         }
#         if ($data =~ /\r\n\r\n/) {
#             my ($metadata, $file_data) = split(/\r\n\r\n/, $data, 2);
#             # print("DATA123: $file_data\n");
#             extract_metadata($metadata, $client_fd, $file_data);
#             $epoll::clients{$client_fd}{finished_metadata} = 1;
#         }
#     }

#     if (!$epoll::clients{$client_fd}{finished_metadata}) {
#         $epoll::clients{$client_fd}{upload_tries}++;
#     }
# }
sub get_metadata {
    my ($client_fd) = @_;
    my $client = $epoll::clients{$client_fd};

    if ($client->{upload_tries}++ > 6) {
        return;
    }

    my $data = $client->{buffer};
    if (!$client->{read_temp_file}) {
        $data .= body_utils::load_temp_file($client->{temp_file});
        my $upload_meta_data_file = "/tmp/upload_meta_data_$client_fd";
        open my $fh, '>', $upload_meta_data_file or die "Cannot open file: $!";
        binmode $fh;
        print $fh "{}";
        close $fh;
        $client->{read_temp_file} = 1;      
    }
    print("DATA: $data\n");
    print("SOCKET: $client->{socket}\n");

    my $bytes_read = sysread($client->{socket}, my $buffer, 1024);
    $data .= $buffer if $bytes_read > 0;

    my $boundary = $client->{boundary} or die "Boundary not defined";
    $client->{buffer} = '';

    my @parts = split(/(?:\r\n|^)--\Q$boundary\E(?:--)?(?=\r\n|--)/, $data);

    shift @parts if @parts;

    foreach my $part (@parts) {
        next if $part =~ /^\s*$/;

        if ($part =~ /--\s*$/) {
            $client->{finished_metadata} = 1;
            last;
        }

        if ($part =~ /^(.*?)\r\n\r\n(.*)$/s) {
            my ($headers, $body) = ($1, $2);

            if ($headers =~ /filename="([^"]*)"/) {
                extract_metadata($headers, $client_fd, $body);
                $client->{finished_metadata} = 1;
                last;
            } else {
                my ($name) = $headers =~ /name="([^"]*)"/;
                next unless $name;
                $name = user_utils::encode_uri($name);

                my $upload_meta_data_file = "/tmp/upload_meta_data_$client_fd";
                my $json = {};
                if (-e $upload_meta_data_file) {
                    open my $meta_fh, '<', $upload_meta_data_file or die "Cannot open file: $!";
                    local $/;
                    $json = decode_json(<$meta_fh>);
                    close $meta_fh;
                }

                $json->{$name} = $body;

                open my $meta_fh, '>', $upload_meta_data_file or die "Cannot open file: $!";
                print $meta_fh encode_json($json);
                close $meta_fh;
            }
        } else {
            $client->{buffer} .= $part;
        }
    }
}


sub extract_metadata {
    my ($headers, $client_fd, $file_data) = @_;
    my $client = $epoll::clients{$client_fd};
    print("HEADER: $headers\n");
    print("FILE DATA: $file_data\n");
    my ($filename) = $headers =~ /filename="(.*)"/;
    $filename = user_utils::encode_uri($filename) if $filename;

    my ($content_type) = $headers =~ /Content-Type: (.*)/; 

    my ($name) = $headers =~ /name="(.*)"; filename/;

    $client->{filename} = $filename;
    $client->{content_type} = $content_type;
    $client->{name} = $name;

    print("FILENAME: $filename\n");
    print("CONTENT TYPE: $content_type\n");
    print("NAME: $name\n");

    create_file($client_fd, $file_data);
}

# sub extract_metadata {
#     my ($metadata, $client_fd, $file_data) = @_;
#     # print("METADATA: $metadata\n");
#     # die;
#     my ($filename) = $metadata =~ /filename="(.*)"/;
#     $filename = user_utils::encode_uri($filename);
#     my ($content_type) = $metadata =~ /Content-Type: (.*)/; 
#     my ($name) = $metadata =~ /name="(.*)"; filename/;
#     $epoll::clients{$client_fd}{filename} = $filename;
#     $epoll::clients{$client_fd}{content_type} = $content_type;
#     $epoll::clients{$client_fd}{name} = $name;
#     # print("FILE DATA: $file_data\n");
#     print("FILENAME: $filename\n");
#     print("CONTENT TYPE: $content_type\n");
#     print("NAME: $name\n");
#     create_file($client_fd, $file_data);
# }

sub create_file {
    my ($client_fd, $file_data) = @_;
    print("CREATING FILE\n");
    my $uuid = $main::user->{uuid};

    if (!$uuid) {
        http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_401());
        return;
    }

    my $base_dir = getcwd;
    my $user_path = "$base_dir/Data/UserData/Users/$uuid";
    # print("USER PATH: $user_path\n");
    if (!-d $user_path) {
        # print("WADAFUCK\n");
        die;
    }

    my $filepath;
    my $dir_path;

    print("LOCATION: $epoll::clients{$client_fd}{location}\n");
    foreach my $key (keys %locations) {
        print("KEY: $key\n");
        if ($epoll::clients{$client_fd}{location} =~ /$key/) {
            ($filepath, $dir_path) = $locations{$key}($client_fd, $user_path);
            last
        } 
    }    

    print("STILL ALIVE\n");
    print("FILEPATH: $filepath\n");
    print("DIR PATH: $dir_path\n");
    if (!$filepath) {
        http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_404());
        return;
    }

    # if (-e $filepath) {
    #     http_utils::serve_error($epoll::clients{$client_fd}{client_socket}, HTTP_RESPONSE::ERROR_409("File already exists"));
    #     $epoll::clients{$client_fd}{error} = 1;
    #     return;
    # }

    # print("CREATING FILEPATH: $filepath\n");

    $epoll::clients{$client_fd}{filepath} = $filepath;
    $epoll::clients{$client_fd}{dir_path} = $dir_path;
    # print("FILE DATA: $file_data\n");

    my $boundary = $epoll::clients{$client_fd}{boundary};
    my $write_data;
    my $save_data;


    if ($file_data =~ /$boundary--\r\n/) {
        $epoll::clients{$client_fd}{finished} = 1;
        $write_data = $file_data;
    } else {
        $write_data = substr($file_data, 0, -$save_length);
        $save_data  = substr($file_data, -$save_length);
    }

    if ($save_data) {
        $epoll::clients{$client_fd}{buffer} = $save_data;
    }

    open my $fh, '>', $filepath or die "Cannot open file: $!";
    binmode $fh; 
    print $fh $write_data;
    close $fh;
    # print("FILE CREATED, now reading until finished\n");
}

sub create_game_launcher_path {
    my ($client_fd, $user_path) = @_;
    $epoll::clients{$client_fd}{game} = 1;
    my $base_dir = getcwd();
    my $game_id = csharp_game::create_game_id();
    $epoll::clients{$client_fd}{game_id} = $game_id;

    my $launcher_path = "$base_dir/Data/CSharpGameLauncher";
    if (!-d $launcher_path) {
        mkdir $launcher_path or die "Cannot create directory: $!";
    }
    my $games_path = "$launcher_path/Games";
    if (!-d $games_path) {
        mkdir $games_path or die "Cannot create directory: $!";
    }
    my $game_path = "$games_path/$game_id";
    if (-d $game_path) {
        http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_409("Game already exists"));
        return;
    }
    mkdir $game_path or die "Cannot create directory: $!";
    my $metadata_file = "$game_path/metadata.json";
    open my $fh, '>', $metadata_file or die "Cannot open file: $!";
    print $fh "{}";
    close $fh;

    $epoll::clients{$client_fd}{game_id} = $game_id;
    my $new_game_id = $epoll::clients{$client_fd}{game_id};
    print "Type2: " . (0 + $new_game_id eq $new_game_id ? "Integer" : "String") . "\n";

    my $games_path = "$game_path/Versions";
    if (!-d $games_path) {
        mkdir $games_path or die "Cannot create directory: $!";
    }
    my $file_path = "$games_path/$epoll::clients{$client_fd}{filename}";
    return ($file_path, $games_path);
}

sub create_ploud_path {
    my ($client_fd, $user_path, $file_data) = @_;

    my $ploud_path = "$user_path/ploud";
    # print("PLOUD PATH: $ploud_path\n");
    if (!-d $ploud_path) {
        mkdir $ploud_path or die "Cannot create directory: $!";
    }
    my $dir_path = "$ploud_path/$epoll::clients{$client_fd}{filename}";
    if (!-d $dir_path) {
        mkdir $dir_path or die "Cannot create directory: $!";
    }
    my $filepath = "$dir_path/$epoll::clients{$client_fd}{filename}";
    # print("FILEPATH: $filepath\n");


    return ($filepath, $dir_path);
}

sub create_streaming_path {
    my ($client_fd, $user_path) = @_;

    my $streaming_path = "$user_path/Streaming";
    # print("STREAMING PATH: $streaming_path\n");
    if (!-d $streaming_path) {
        mkdir $streaming_path or die "Cannot create directory: $!";
    }
    my $videos_path = "$streaming_path/Videos";
    if (!-d $videos_path) {
        mkdir $videos_path or die "Cannot create directory: $!";
    }
    my $video_id = video_utils::create_new_video_id();
    my $dir_path = "$videos_path/$video_id";
    if (!-d $dir_path) {
        mkdir $dir_path or die "Cannot create directory: $!";
    }
    my $filepath = "$dir_path/$epoll::clients{$client_fd}{filename}";
    # print("FILEPATH: $filepath\n");

    $epoll::clients{$client_fd}{video} = 1;
    $epoll::clients{$client_fd}{video_id} = $video_id;


    return ($filepath, $dir_path);
}

my %update_categorys = (
    "channel" => \&update_channel,
    "videos" => \&update_videos,
);

sub create_streaming_update_path {
    my ($client_fd, $user_path) = @_;

    my $streaming_path = "$user_path/Streaming";
    if (!-d $streaming_path) {
        http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_404());
        return;
    }
    # print("LOCATION: $epoll::clients{$client_fd}{location}\n");
    my ($username, $category, $video_id, $item) = $epoll::clients{$client_fd}{location} =~ /^\/update\/streaming\/manage\/channel\/([^\/]+)\/([^\/]+)(?:\/([^\/]+))?\/([^\/]+)$/;
    # print("USERNAME: $username\n");
    # print("CATEGORY: $category\n");
    # print("VIDEO ID: $video_id\n");
    # print("ITEM: $item\n");
    if (!$username || !$category || !$item) {
        http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_404());
        return;
    }
    if (!channel_utils::has_manage_access(user_utils::get_uuid_by_username($username))) {
        http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_401());
        return;
    }

    if (!$update_categorys{$category}) {
        http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_404());
        return;
    }
    my ($filepath, $dir_path) = $update_categorys{$category}($streaming_path, $video_id, $item, $client_fd);


    $filepath = "$dir_path/$epoll::clients{$client_fd}{filename}";
    # print("FILEPATH: $filepath\n");

    
    
    $epoll::clients{$client_fd}{update} = 1;

    return ($filepath, $dir_path);
}

my %update_channel_items = (
    "icon" => \&update_channel_icon,
    "banner" => \&update_channel_banner,
);

sub update_channel {
    my ($streaming_path, $video_id, $item, $client_fd) = @_;

    my $channel_path = "$streaming_path/Channel";
    if (!-d $channel_path) {
        mkdir $channel_path or do {
            http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_500("Cannot create directory"));
            return;
        };
    }

    if (!$update_channel_items{$item}) {
        http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_404());
        return;
    }

    my ($filepath, $dir_path) = $update_channel_items{$item}($channel_path, $client_fd);

    return ($filepath, $dir_path);
}

sub update_channel_icon {
    my ($channel_path, $client_fd) = @_;
    $epoll::clients{$client_fd}{is_icon} = 1;

    my $dir_path = "$channel_path/Icon";
    if (!-d $dir_path) {
        mkdir $dir_path or do {
            http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_500("Cannot create directory"));
            return;
        };
    }
    my $filepath = "$dir_path/$epoll::clients{$client_fd}{filename}";
    # print("FILEPATH: $filepath\n");
    my $base_dir = getcwd;
    my ($trimmed_filepath) = $filepath =~ /$base_dir\/(.*)/;

    my $old_icon;
    my $icon_file = "$dir_path/channel_icon.json";
    if (!-e $icon_file) {
        open my $fh, '>', $icon_file or die "Cannot open file: $!";
        print $fh encode_json({icon => $trimmed_filepath});
        close $fh;
    } else {
        open my $fh, '<', $icon_file or die "Cannot open file: $!";
        my $data = do { local $/; <$fh> };
        close $fh;
        my $icon_data = decode_json($data);
        $old_icon = $icon_data->{icon};
        $icon_data->{icon} = $trimmed_filepath;
        if ($old_icon) {
            my $new_path = $old_icon;
            if ($trimmed_filepath eq $old_icon) {
                $new_path = rename_old_file($old_icon);
            }
            foreach my $old_file (@{$icon_data->{old_icons}}) {
                if ($old_file eq $old_icon) {
                    $new_path = rename_old_file($old_icon);
                    last;
                }
            }
            $icon_data->{old_icons}->[$#{$icon_data->{old_icons}} + 1] = $new_path;

        }
        open my $icon_fh, '>', $icon_file or die "Cannot open file: $!";
        print $icon_fh encode_json($icon_data);
        close $icon_fh;
    }

    return ($filepath, $dir_path);
}

sub rename_old_file {
    my ($filepath) = @_;

    my ($part_path, $filename) = $filepath =~ /(.*)\/([^\/]+)$/;
    my ($filename, $file_extension) = $filename =~ /(.*)\.(.*)$/;
    my $new_filename;
    my $counter = 1;
    my $base_dir = getcwd;
    my $new_filepath;
    while (1) {
        last if $counter > 10;
        $new_filename = "$filename$counter.$file_extension";
        $new_filepath = "$base_dir/$part_path/$new_filename";
        if (!-e $new_filepath) {
            my $old_path = "$base_dir/$filepath";
            print("FILEPATH: $old_path\n");
            rename $old_path, $new_filepath or die "Cannot rename file: $!";
            $new_filepath = "$part_path/$new_filename";
            last;
        } else {
            $counter++;
        }
    }
    if (!$new_filepath) {
        $new_filepath = $filepath;
    }
    return $new_filepath;
}

sub update_channel_banner {
    my ($channel_path, $client_fd) = @_;

    my $dir_path = "$channel_path/Banner";
    if (!-d $dir_path) {
        mkdir $dir_path or do {
            http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_500("Cannot create directory"));
            return;
        };
    }
    my $filepath = "$dir_path/$epoll::clients{$client_fd}{filename}";
    # print("FILEPATH: $filepath\n");

    return ($filepath, $dir_path);
}

sub update_videos {
    my ($streaming_path, $video_id, $item, $client_fd) = @_;

    my $dir_path = "$streaming_path/Videos/$video_id";
    my $filepath = "$dir_path/$epoll::clients{$client_fd}{filename}";
    # print("FILEPATH: $filepath\n");


    my $metadata_file_path = "$dir_path/metadata.json";
    # print("METADATA FILE PATH: $metadata_file_path\n");
    open my $fh, '<', $metadata_file_path or die "Cannot open file: $!";
    my $data = do { local $/; <$fh> };
    close $fh;
    # print("DATA: $data\n");
    my $meta_data = decode_json($data);

    if (!$meta_data) {
        http_utils::serve_error($epoll::clients{$client_fd}{socket}, HTTP_RESPONSE::ERROR_404());
        return;
    }
    
    my $old_thumbnail = $meta_data->{thumbnail};
    foreach my $old_file (@{$meta_data->{old_thumbnails}}) {
        if ($old_file eq $old_thumbnail) {
            my ($filename, $file_extension) = $old_thumbnail =~ /(.*)\.(.*)$/;
            my $new_filename;
            my $counter = 1;

            while (1) {
                if ($old_file =~ /\Q$filename\E(\d*)\.\Q$file_extension\E$/) {
                    my $num = $1 || 0;
                    $num++;
                    $new_filename = "$filename$num.$file_extension";
                } else {
                    $new_filename = "$filename$counter.$file_extension";
                    $counter++;
                }
                last unless grep { $_ eq $new_filename } @{$meta_data->{old_thumbnails}};
                if ($counter > 10) {
                    serve_error($client_fd, HTTP_RESPONSE::ERROR_500("Too many Thumbnails, delete old ones"));
                }
            }
        }
            
    }
    push @{$meta_data->{old_thumbnails}}, $old_thumbnail;
    # print("OLD THUMBNAILS: $meta_data->{old_thumbnails}\n");
    my $base_dir = getcwd;
    my ($trimmed_filepath) = $filepath =~ /$base_dir\/(.*)/;
    $meta_data->{thumbnail} = $trimmed_filepath;

    open my $meta_fh, '>', $metadata_file_path or die "Cannot open file: $!";
    print $meta_fh encode_json($meta_data);
    close $meta_fh;

    return ($filepath, $dir_path, $meta_data);
}

# my $sysread_bytes = 0;
sub write_file_until_boundary {
    my ($client_fd) = @_;
    my $client = $epoll::clients{$client_fd};
    
    my $bytes_read = sysread($client->{socket}, my $buffer, 1024*256);
    if ($bytes_read == 0) {
        warn "Client disconnected";
        $client->{error} = 1;
        return;
    }
    # print("SYSREAD BYTES: $bytes_read\n");
    # $sysread_bytes = $bytes_read;
    # print("BUFFER: $client->{buffer}\n");
    $client->{buffer} .= $buffer;

    process_buffer($client_fd);
}
sub process_buffer {
    my ($client_fd) = @_;
    my $client = $epoll::clients{$client_fd};
    my $boundary = "--$client->{boundary}";
    my $buffer = $client->{buffer};
    if (!$buffer) {
        die "No buffer";
    }

    if ($buffer !~ /$boundary/) {
        # print("BUFFER LENGTH: ". length($buffer) ."\n");
        # my ($write_data, $save_data) = $buffer =~ /^(.*)(\r(?!.*\r).*$)/s;
        my $write_data = substr($buffer, 0, -$save_length);
        my $save_data  = substr($buffer, -$save_length);
        # print("Write data length: " . length($write_data) . "\n");
        if (!$write_data && !$save_data) {
            # print("WRITE = BUFFER\n");
            $write_data = $buffer;
        }
        write_to_file($client_fd, $write_data);
        if ($save_data) {
            # print("SAVING DATA\n");
            $client->{buffer} = $save_data;
            return;
        } else {
            $client->{buffer} = '';
            return;
        }
    } else {
        # print("BOUNDARY FOUND\n");
    }
    while ($buffer =~ /(.*?)((?:\r\n)?$boundary(?:--)?(?:\r\n)?)(.*)/s) {
        my ($before_boundary, $buffer_boundary, $remaining) = ($1, $2, $3, $4, $5);
        # print("REMAINING: $remaining\n");
        write_to_file($client_fd, $before_boundary) if $before_boundary;

        if ($buffer_boundary =~ /--\r\n/) {
            # warn "Final boundary detected. Ending processing.";
            finalize_processing($client_fd);
            $client->{buffer} = '';
            return;
        }

        $buffer = $remaining;
        my $keep_buffer;
        my $need_one_more = 0;
        my $keep_buffer_need = 0;
        while ($buffer =~ /^(.*?\r\n\r\n)(.*?)(?=((?:\r\n)?$boundary(--\r\n)?)|$)(.*)/s) {
            my ($metadata, $body, $boundary_data, $ending, $after_boundary) = ($1, $2, $3, $4, $5);
            handle_form_metadata($client_fd, $metadata, $body);
            if ($boundary_data && $boundary_data =~ /$boundary/) {
                $need_one_more = 1;
                $keep_buffer = $boundary_data . $after_boundary;
            } elsif ($boundary_data && $boundary_data !~ /$boundary/) {
                $keep_buffer = $boundary_data;
                $keep_buffer_need = 1;
                last;
            } elsif (!$boundary_data) {
                $keep_buffer = '';
                $keep_buffer_need = 0;
                $need_one_more = 0;
            }
            if ($ending) {
                finalize_processing($client_fd);
                $client->{buffer} = '';
                return;
            }
            $buffer =~ s/^(.*?\r\n\r\n)(.*?)(?=$boundary|$)//s; 
        }

        if ($need_one_more || $keep_buffer_need) {
            # print("NEED ONE MORE\n");
            # print("KEEP BUFFER: $keep_buffer\n");
            # print("BUFFER: $buffer\n");
            $client->{buffer} = $keep_buffer;

            return;
        }

        if ($buffer !~ /^\s*$/) {
            # print("BUFFER: $buffer\n");
            $client->{buffer} = $buffer;
            warn "Incomplete data detected, saving for next chunk.";
            return;
        }
    }

    # print("LEFTOVER DATA: $buffer\n");
    $client->{buffer} = $buffer;
}
# my $total_bytes = 0;
sub write_to_file {
    my ($client_fd, $data) = @_;
    my $client = $epoll::clients{$client_fd};

    if (!$data) {
        return;
    }

    open my $fh, '>>', $client->{write_file} or die "Cannot open file: $!";
    binmode $fh;
    print $fh $data;
    close $fh;

    # $total_bytes += length($data);

    # warn "Wrote data to file: " . length($data) . " bytes.";
    # if (length($data) != $sysread_bytes) {
    #     warn "total bytes: $total_bytes";
    #     die "Wrong length";
    # }
}


sub handle_form_metadata {
    my ($client_fd, $metadata, $body) = @_;
    my $client = $epoll::clients{$client_fd};

    chomp($metadata);
    # print($metadata);
    push @{$client->{forms}}, $metadata;
    
    if ($metadata =~ /Content-Disposition: form-data; name="([^"]+)"/) {
        my $name = $1;
        my $todo = $upload_name_list{$name};
        if (!$todo) {
            warn "No action defined for form data: $name";
            return;
        }
        # print("TODO: $todo\n");
        # print("NAME: $name\n");
        my $upload_meta_data_file = "/tmp/upload_meta_data_$client_fd";
        if (!-e $upload_meta_data_file) {
            open my $fh, '>', $upload_meta_data_file or die "Cannot open file: $!";
            binmode $fh;
            print $fh "{}";
            close $fh;
        }

        open my $meta_fh, '<', $upload_meta_data_file or warn "Cannot open file: $!";
        local $/;
        my %upload_meta_data = %{ decode_json(<$meta_fh>) };
        close $meta_fh;

        if ($todo eq "metadata") {
            # ! if body is not done by end of request, doesnt work, needs fix
            if (!$body) {
                die "No body";
            }
            # print("Writing metadata: $name => $body\n");
            $upload_meta_data{$name} = $body;
            $client->{write_file} = "/tmp/noUse";
        } elsif ($todo eq "thumbnail") {
            if ($metadata =~ /filename="(.*)"/) {
                my $filename = $1;
                my $base_dir = getcwd;
                my $file_path = "$client->{dir_path}/$filename";
                my ($trimmed_filepath) = $file_path =~ /$base_dir\/(.*)/; 
                $client->{write_file} = $trimmed_filepath;
                $upload_meta_data{$name} = $client->{write_file};

                open my $fh, '>', $client->{write_file} or die "Cannot open file: $!";
                binmode $fh;
                print $fh $body;
                close $fh;
                # print("Thumbnail saved to $client->{write_file}\n"); 
                # print("BODY: $body\n");
            } else {
                # print("NO FILENAME\n");
                die;
            }
        } 
        open $meta_fh, '>', $upload_meta_data_file or die "Cannot open file: $!";
        binmode $meta_fh;
        print $meta_fh encode_json(\%upload_meta_data);
        close $meta_fh;
    }
}

sub finalize_processing {
    my ($client_fd) = @_;
    my $client = $epoll::clients{$client_fd};
    $client->{finished} = 1;

    # Output processed form metadata
    # foreach my $form (@{$client->{forms}}) {
        # print "=========== FORM METADATA ===========\n";
        # print($form."\n");
        # print "=====================================\n";
    # }
}
1;