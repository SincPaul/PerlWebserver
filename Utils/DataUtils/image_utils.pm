package image_utils;

use strict;
use warnings;

use Cwd;
use JSON;
use IO::Epoll;

sub get_thumbnail {
    my ($video_id, $client_socket) = @_;

    my $base_dir = getcwd();
    my $video_path = "$base_dir/Data/Streaming/Videos";
    my $videos_file = "$video_path/videos.txt";
    my $full_file_path;
    open my $fh, "<", $videos_file;
    
    # print("VIDEO ID: $video_id\n");
    while (my $line = <$fh>) {
        chomp $line;
        # print("LINE: $line\n");
        if ($line !~ /$video_id/) {
            next;
        }
        my $meta_data_file = "$base_dir/$line";
        # print("META DATA FILE: $meta_data_file\n");
        open my $meta_fh, "<", $meta_data_file;
        my $meta_data = do { local $/; <$meta_fh> };
        close $meta_fh;
        if (!$meta_data) {
            next;
        }
        my $video_data = decode_json($meta_data);

        my $file_path = $video_data->{thumbnail};

        $full_file_path = "$base_dir/$file_path";
        # print("Full file path: $full_file_path\n");
        last;
    }
    close $fh;
    
    get_image($full_file_path, $client_socket, $video_id);
}

sub get_channel_icon {
    my ($channel_id, $client_socket) = @_;

    my $base_dir = getcwd();
    my $channel_path = "$base_dir/Data/UserData/Users/$channel_id/Streaming/Channel";
    # print("CHANNEL PATH: $channel_path\n");
    if (!-d $channel_path) {
        # warn "no channel path\n";
        get_default_channel_icon($client_socket);
        return;
    }
    my $channel_metadata_file = "$channel_path/Icon/channel_icon.json";
    if (!-e $channel_metadata_file) {
        warn "no icon file\n";
        get_default_channel_icon($client_socket);
        return;
    }
    my $full_file_path;
    open my $fh, "<", $channel_metadata_file;
    my $icon_data = do { local $/; <$fh> };
    close $fh;
    my $icon_data_json = decode_json($icon_data);
    my $icon_path = $icon_data_json->{icon};
    if (!$icon_path) {
        warn "no icon file1\n";
        get_default_channel_icon($client_socket);
        return;
    }
    $full_file_path = "$base_dir/$icon_path";
    if (!-e $full_file_path) {
        warn "no icon file2\n";
        get_default_channel_icon($client_socket);
        return;
    }
    get_image($full_file_path, $client_socket);
}

sub get_default_channel_icon {
    my ($client_socket) = @_;

    my $base_dir = getcwd();
    my $file_path = "$base_dir/Data/Streaming/Images/default_channel_icon.png";
    if (!-e $file_path) {
        my $error = HTTP_RESPONSE::ERROR_404("Image not found");
        http_utils::send_response($client_socket, $error);
        return;
    }
    get_image($file_path, $client_socket);
}

sub get_channel_banner {
    my ($channel_id, $client_socket) = @_;

    my $base_dir = getcwd();
    my $channel_path = "$base_dir/Data/UserData/Users/$channel_id/Streaming";
    if (!-d $channel_path) {
        get_default_channel_banner($client_socket);
        return;
    }
    my $channel_metadata_file = "$channel_path/channel_metadata.txt";
    if (!-e $channel_metadata_file) {
        get_default_channel_banner($client_socket);
        return;
    }
    my $full_file_path;
    open my $fh, "<", $channel_metadata_file;
    my $channel_metadata = do { local $/; <$fh> };
    close $fh;
    my $channel_data = decode_json($channel_metadata);
    my $file_path = $channel_data->{channel_banner};
    $full_file_path = "$base_dir/$file_path";
    if (!-e $full_file_path) {
        get_default_channel_banner($client_socket);
        return;
    }
    get_image($full_file_path, $client_socket);
}

sub get_default_channel_banner {
    my ($client_socket) = @_;

    my $base_dir = getcwd();
    my $file_path = "$base_dir/Data/Streaming/Images/default_channel_banner.png";
    if (!-e $file_path) {
        my $error = HTTP_RESPONSE::ERROR_404("Image not found");
        http_utils::send_response($client_socket, $error);
        return;
    }
    get_image($file_path, $client_socket);
}

sub get_image {
    my ($full_file_path, $client_socket, $filename) = @_;

    if (!-e $full_file_path) {
        my $error = HTTP_RESPONSE::ERROR_404("Image not found");
        http_utils::send_response($client_socket, $error);
        return;
    }

    my $file_size = -s $full_file_path;
    print("FILE PATH: $full_file_path\n");
    print("FILE SIZE: $file_size\n");
    open my $fh, '<', $full_file_path or die "Cannot open file: $!";
    $epoll::clients{fileno $client_socket}{filestream} = {
        file => $fh,
        file_size => $file_size,
        file_pos => 0,
        chunk_size => 4096,
    };
    epoll_ctl($main::epoll, EPOLL_CTL_MOD, fileno $client_socket, EPOLLIN | EPOLLOUT) >= 0 || die "Can't add client socket to main::epoll: $!";
    $epoll::clients{fileno $client_socket}{"has_out"} = 1;
    # print("Added client socket to writeepoll\n");
    my ($file_ext) = $full_file_path =~ /\.(\w+)$/; 
    if (!$filename) {
        $filename = "img";
    }
    my $header = HTTP_RESPONSE::OK_WITH_DATA_HEADER_AND_CACHE($file_size, "$filename.$file_ext", "image/$file_ext");
    send($client_socket, $header, 0);

    main::handle_filestream(fileno $client_socket);
}

my %supported_img_types = (
    "png" => \&get_png_dimensions,
);

sub get_image_dimensions {
    my ($filepath) = @_;

    print("FILEPATH: $filepath\n");
    my ($ext) = $filepath =~ /\.(\w+)$/;

    print("EXT: $ext\n");
    if (!$supported_img_types{$ext}) {
        return;
    }

    return $supported_img_types{$ext}->($filepath);
}

sub get_png_dimensions {
    my ($filepath) = @_;

    open my $fh, '<', $filepath or die "Cannot open file: $!";
    binmode $fh;
    
    read $fh, my $signature, 8;
    print("SIGNATURE: $signature\n");
    if ($signature ne "\x89PNG\x0d\x0a\x1a\x0a") {
        print("Not a PNG file\n");
        return;
    }

    read $fh, my $ihdr_chunk, 8;
    read $fh, my $width_data, 4;
    read $fh, my $height_data, 4;
    my $width = unpack('N', $width_data);
    my $height = unpack('N', $height_data);

    return ($width, $height);
}
1;