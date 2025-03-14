package game_utils;

use strict;
use warnings;

use JSON;
use Cwd;

use JSON;
use Cwd;

my %game_types = (
    "memory" => \&memory_game_utils::handle_memory,
);


sub handle_game_index {
    my ($message, $client_socket) = @_;

    # print("HANDLING GAME INDEX\n");

    foreach my $game (keys %game_types) {
        if ($message->{"game"} eq $game) {
            return $game_types{$game}->($message, $client_socket);
        }
    }
}

sub get_spectate_games {
    my ($game) = @_;

    my @spectate_games;
    foreach my $game_id (keys %memory::spectate_games) {
        push(@spectate_games, $game_id);
        # print("SPECTATE GAMES: $game_id\n");
    }


    return @spectate_games;
}

sub initialize_game {
    my ($client_socket, $temp_file) = @_;

    my $data = body_utils::load_temp_file($temp_file);
    my $json = decode_json($data);

    my $game_name = $json->{"game_name"};
    my $game_version = $json->{"game_version"};
    my $force_new_version = $json->{"force_new_version"};

    my $game_id = csharp_game::create_game_id($client_socket);

    my $base_dir = getcwd();
    my $game_dir = "$base_dir/Data/CSharpGameLauncher/Games/$game_id";
    if (!-d $game_dir) {
        mkdir $game_dir;
    }

    my $metadata = {
        name => $game_name,
        version => $game_version,
        hash => "",
        force_new_version => \$force_new_version
    };

    my $metadata_file = "$game_dir/metadata.json";
    my $metadata_text = encode_json($metadata);

    open my $fh, '>', $metadata_file or die "Could not open file '$metadata_file' $!";
    print $fh $metadata_text;
    close $fh;

    return $game_id;
}

sub setup_github {
    my ($client_socket, $temp_file) = @_;

    # print("SETUP GITHUB\n");

    my $data = body_utils::load_temp_file($temp_file);
    # print("DATA: $data\n");
    my $json = decode_json($data);
    # print("JSON: $json\n");
    my $game_id = $json->{"game_id"};
    my $github_url = $json->{"github_link"};
    my $github_access_token = $json->{"access_token"};
    my $github_access_token_username = $json->{"access_token_username"};

    # print("GITHUB URL: $github_url\n");
    # print("GITHUB ACCESS TOKEN: $github_access_token\n");
    if (!github_utils::validate_github_link($github_url, $github_access_token)) {
        # print("FAILED TO VALIDATE GITHUB LINK\n");
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Invalid github link"));
        return;
    }

    my $base_dir = getcwd();
    my $game_dir = "$base_dir/Data/CSharpGameLauncher/Games/$game_id";
    my $metadata_file = "$game_dir/metadata.json";

    open my $fh, '<', $metadata_file or die "Could not open file '$metadata_file' $!";
    my $metadata_text = do { local $/; <$fh> };
    close $fh;

    my $metadata = decode_json($metadata_text);
    $metadata->{github_url} = $github_url;
    if ($github_access_token) {
        $metadata->{access_token} = $github_access_token;
        $metadata->{access_token_username} = $github_access_token_username;
    }

    # print("METADATA: $metadata\n");
    foreach my $key (keys %$metadata) {
        # print("KEY: $key\n");
        # print("VALUE: $metadata->{$key}\n\n");
        if (user_utils::is_int($metadata->{$key}) && $metadata->{$key} == 1) {
            $metadata->{$key} = \1;
        }
        if (user_utils::is_int($metadata->{$key}) && $metadata->{$key} == 1) {
            $metadata->{$key} = \0;
        }
    }


    $metadata_text = encode_json($metadata);

    open $fh, '>', $metadata_file or die "Could not open file '$metadata_file' $!";
    print $fh $metadata_text;
    close $fh;

    http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK("Github Credenntials added"));
}

sub publish_github {
    my ($client_socket, $temp_file) = @_;

    # maybe do later
    return 0;

    my $data = body_utils::load_temp_file($temp_file);
    my $json = decode_json($data);
    my $game_id = $json->{"game_id"};

    my $base_dir = getcwd();
    my $game_dir = "$base_dir/Data/CSharpGameLauncher/Games/$game_id";
    my $metadata_file = "$game_dir/metadata.json";
    if (!-e $metadata_file) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Game not found"));
        return;
    }

    open my $fh, '<', $metadata_file or die "Could not open file '$metadata_file' $!";
    my $metadata_text = do { local $/; <$fh> };
    close $fh;

    my $metadata = decode_json($metadata_text);
    my $github_url = $metadata->{github_url};
    my $github_access_token = $metadata->{access_token};
    my $github_access_token_username = $metadata->{access_token_username};

    if (!github_utils::validate_github_link($github_url, $github_access_token)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Invalid github link"));
        return;
    }

    my $game_name = $metadata->{name};
    my $game_version = $metadata->{version};

    my $version_dir = "$game_dir/$game_version";
    if (!-d $version_dir) {
        mkdir $version_dir;
    }

    if (!github_utils::pull_from_github($github_url, $github_access_token, $github_access_token_username, $version_dir)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Could not pull from github"));
        return;
    }



}
1;