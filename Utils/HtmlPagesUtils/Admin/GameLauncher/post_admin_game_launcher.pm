package post_admin_game_launcher;

use strict;
use warnings;

use JSON;

sub post_admin_initialize_game {
    my ($client_socket, $route, $temp_file) = @_;

    if ($main::user) {
        my $role = user_utils::get_role();
        if ($role ne "admin") {
            return 0;
        }
    } else {
        return 0;
    }

    my $game_id = game_utils::initialize_game($client_socket, $temp_file);
    if (!$game_id) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Could not initialize game"));
        return;
    }

    my $json = {
        game_id => $game_id
    };

    my $json_text = encode_json($json);
    my $response = HTTP_RESPONSE::OK($json_text);
    http_utils::send_http_response($client_socket, $response);
}

sub post_admin_upload_github {
    my ($client_socket, $route, $temp_file) = @_;

    print("ADDING TO GITHUB\n");

    if ($main::user) {
        my $role = user_utils::get_role();
        if ($role ne "admin") {
            return 0;
        }
    } else {
        return 0;
    }

    print("ADDING TO GITHUB\n");

    game_utils::setup_github($client_socket, $temp_file);
}

sub post_admin_publish_github {
    my ($client_socket, $route, $temp_file) = @_;

    print("PUBLISHING TO GITHUB\n");

    if ($main::user) {
        my $role = user_utils::get_role();
        if ($role ne "admin") {
            return 0;
        }
    } else {
        return 0;
    }

    print("PUBLISHING TO GITHUB\n");

    game_utils::publish_github($client_socket, $temp_file);
}
1;