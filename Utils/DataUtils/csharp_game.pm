package csharp_game;

use strict;
use warnings;

use Cwd;
use JSON;
use IO::Epoll;

sub get_game_list {
    my ($client_socket) = @_;

    my $base_dir = getcwd();
    my $game_list = "$base_dir/Data/CSharpGameLauncher/Games/gamelist.json";
    if (!-e $game_list) {
        return;
    }
    open my $fh, '<', $game_list or do {
        return;
    };
    my $data = do { local $/; <$fh> };
    print("DATA: $data\n");
    # my $json = encode_json($data);
    my $response = HTTP_RESPONSE::OK_WITH_DATA($data, "games.json");
    http_utils::send_http_response($client_socket, $response);
    return;
}

sub get_game_stats {
    my ($client_socket, $path) = @_;
    # print("PATH: $path\n");
    $path = lc $path;
    my ($game_id) = $path =~ /gamelauncher\/gamestats\/(.*)/;
    my $base_dir = getcwd();
    my $game_metadata_file = "$base_dir/Data/CSharpGameLauncher/Games/$game_id/metadata.json";
    if (!-e $game_metadata_file) {
        return;
    }
    open my $fh, '<', $game_metadata_file or do {
        return;
    };
    my $data = do { local $/; <$fh> };
    close $fh;
    my $json = decode_json($data);
    # print("JSON: $json\n");
    my $version = $json->{version};
    my $game_stats_file = "$base_dir/Data/CSharpGameLauncher/Games/$game_id/Versions/$version/metadata.json";
    if (!-e $game_stats_file) {
        return;
    }
    open $fh, '<', $game_stats_file or do {
        return;
    };
    $data = do { local $/; <$fh> };
    close $fh;
    $json = decode_json($data);
    $version = $json->{version};
    my $hash = $json->{hash};
    my ($extension) = $json->{filename} =~ /\.(\w+)$/;
    my $patch_name = "$json->{game_name}-$json->{version}.$extension";
    my $name = $json->{game_name};
    my $id = $json->{id} + 0;
    # print "Type20: " . (0 + $id eq $id ? "Integer" : "String") . "\n";
    my $file_size = $json->{size};
    my $uploaded_at = $json->{uploaded_at};
    my $force_new_version = $json->{force_new_version};
    my $executable = $patch_name;
    if (!$force_new_version) {
        $force_new_version = JSON::false;
    }
    my $send_data = {
        Id => $id,
        Version => $version,
        Hash => $hash,
        Name => $name,
        PatchName => $patch_name,
        Size => $file_size,
        UploadedAt => $uploaded_at,
        Executable => $executable,
        ForceNewVersion => \$force_new_version
    };
    $send_data = encode_json($send_data);
    my $response = HTTP_RESPONSE::OK_WITH_DATA($send_data, "gamestats.json");
    http_utils::send_http_response($client_socket, $response);
    return;
}


sub create_game_id {
    my ($client_socket) = @_;

    
    my $id = user_utils::random_number(6);
    
    while (game_exists($id)) {
        $id = user_utils::random_number(6);;
    }

    # print "Type: " . (0 + $id eq $id ? "Integer" : "String") . "\n";
    return $id;
}

sub game_exists {
    my ($game_id) = @_;

    my $base_dir = getcwd();
    my $game_path = "$base_dir/Data/CSharpGameLauncher/Games/$game_id";
    print("GAME PATH: $game_path\n");
    if (-d $game_path) {
        return 1;
    }

    return 0;
}
sub add_to_gamelist {
    my ($game_id, $game_name) = @_;
    print("GAME NAME1: $game_name\n");
    my $base_dir = getcwd();
    my $launcher_path = "$base_dir/Data/CSharpGameLauncher";
    if (!-d $launcher_path) {
        mkdir $launcher_path;
    }
    my $games_path = "$base_dir/Data/CSharpGameLauncher/Games";
    if (!-d $games_path) {
        mkdir $games_path;
    }
    my $game_list = "$games_path/gamelist.json";
    if (!-e $game_list) {
        open my $fh, '>', $game_list or die "Could not open file '$game_list' $!";
        print $fh "{}";
        close $fh;
    }
    open my $fh, '<', $game_list or do {
        die "Could not open file '$game_list' $!";
    };
    my $data = do { local $/; <$fh> };
    # print("DATA: $data\n");
    my $json = decode_json($data);
    # print("GAME ID $game_id\n");
    # print("GAME NAME $game_name\n");
    $json->{$game_id} = $game_name;
    # print("JSON: $json\n");
    my $new_data = encode_json($json);
    # print("NEW DATA: $new_data\n");
    open $fh, '>', $game_list or die "Could not open file '$game_list' $!";
    print $fh $new_data;
    close $fh;
    return;
}

sub update_game_metadata {
    my ($game_id, $game_name, $version, $hash, $force_new_version) = @_;

    my $base_dir = getcwd();
    my $game_path = "$base_dir/Data/CSharpGameLauncher/Games/$game_id";
    if (!-d $game_path) {
        mkdir $game_path;
    }
    my $metadata_file = "$game_path/metadata.json";
    if (!-e $metadata_file) {
        open my $fh, '>', $metadata_file or die "Could not open file '$metadata_file' $!";
        print $fh "{}";
        close $fh;
    }
    my $new_data = {
        id => $game_id,
        name => $game_name,
        version => $version,
        hash => $hash,
        forceNewVersion => $force_new_version
    };
    $new_data = encode_json($new_data);
    open my $fh, '>', $metadata_file or die "Could not open file '$metadata_file' $!";
    print $fh $new_data;
    close $fh;
}

sub download_game {
    my ($client_socket, $route) = @_;

    $route = lc $route;
    my ($game_id) = $route =~ /gamelauncher\/download\/(.*)/;
    if ($game_id eq "launcher") {
        print("DOWNLOADING LAUNCHER\n");
        download_launcher($client_socket);
        print("DOWNLOADED LAUNCHER\n");
        return;
    } 
    my $base_dir = getcwd();
    my $game_path = "$base_dir/Data/CSharpGameLauncher/Games/$game_id";
    if (!-d $game_path) {
        return;
    }
    my $metadata_file = "$game_path/metadata.json";
    if (!-e $metadata_file) {
        return;
    }
    open my $fh, '<', $metadata_file or do {
        return;
    };
    my $data = do { local $/; <$fh> };
    close $fh;
    my $json = decode_json($data);
    my $version = $json->{version};
    my $game_version_path = "$game_path/Versions/$version";
    if (!-d $game_version_path) {
        return;
    }
    my $metadata_version_file = "$game_version_path/metadata.json";
    if (!-e $metadata_version_file) {
        return;
    }
    open $fh, '<', $metadata_version_file or do {
        return;
    };
    $data = do { local $/; <$fh> };
    close $fh;
    $json = decode_json($data);
    my $file_path = $json->{filepath};
    my $full_file_path = "$base_dir/$file_path";
    my $name = $json->{game_name};
    $version = $json->{version};
    if (!-e $full_file_path) {
        return;
    }
    my $file_size = -s $full_file_path;
    print("FILE PATH: $full_file_path\n");
    print("FILE SIZE: $file_size\n");
    open $fh, '<', $full_file_path or die "Cannot open file: $!";
    $epoll::clients{fileno $client_socket}{filestream} = {
        file => $fh,
        file_size => $file_size,
        file_pos => 0,
        chunk_size => 4096,
    };
    epoll_ctl($main::epoll, EPOLL_CTL_MOD, fileno $client_socket, EPOLLIN | EPOLLOUT) >= 0 || die "Can't add client socket to main::epoll: $!";
    $epoll::clients{fileno $client_socket}{"has_out"} = 1;
    my ($file_ext) = $full_file_path =~ /\.(\w+)$/; 
    my $filename = "$name-$version";
    my $header = HTTP_RESPONSE::OK_WITH_DATA_HEADER_AND_CACHE($file_size, "$filename.$file_ext", "application/octet-stream");
    send($client_socket, $header, 0);

    main::handle_filestream(fileno $client_socket);
}


sub download_launcher {
    my ($client_socket) = @_;

    my $base_dir = getcwd();
    # my $launcher_file_name = "GameLauncher-0.1.exe";
    my $launcher_file_name = "GameLauncherSetup v0.003.exe";
    my $game_file = "$base_dir/Data/CSharpGameLauncher/Launcher/$launcher_file_name";
    print("BONJOUR\n");
    if (!-e $game_file) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("File not found"));
        return;
    }
    my $file_size = -s $game_file;
    open my $fh, '<', $game_file or die "Cannot open file: $!";
    $epoll::clients{fileno $client_socket}{filestream} = {
        file => $fh,
        file_size => $file_size,
        file_pos => 0,
        chunk_size => 4096,
    };
    epoll_ctl($main::epoll, EPOLL_CTL_MOD, fileno $client_socket, EPOLLIN | EPOLLOUT) >= 0 || die "Can't add client socket to main::epoll: $!";
    $epoll::clients{fileno $client_socket}{"has_out"} = 1;
    my $header = HTTP_RESPONSE::OK_WITH_DATA_HEADER_AND_CACHE($file_size, "$launcher_file_name", "application/octet-stream");
    send($client_socket, $header, 0);

    print("FILE SIZE: $file_size\n");
    # main::handle_filestream(fileno $client_socket);
    main::epoll_loop();
}
1;