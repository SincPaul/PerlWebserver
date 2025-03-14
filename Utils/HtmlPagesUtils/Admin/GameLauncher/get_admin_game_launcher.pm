package get_admin_game_launcher;

use strict;
use warnings;

use Cwd;
use JSON;

sub get_admin_game_launcher {
    my ($client_socket) = @_;

    if ($main::user) {
        my $role = user_utils::get_role();
        if ($role ne "admin") {
            return 0;
        }
    } else {
        return 0;
    }

    my $html_content = get_admin_game_launcher_html::get_admin_game_launcher;
    if ($html_content) {
        return $html_content;
    }
}

sub get_admin_game_launcher_add {
    my ($client_socket) = @_;

    if ($main::user) {
        my $role = user_utils::get_role();
        if ($role ne "admin") {
            return 0;
        }
    } else {
        return 0;
    }

    my $html_content = get_admin_game_launcher_add::get_admin_game_launcher_add;
    if ($html_content) {
        return $html_content;
    }
}

sub get_admin_game_launcher_add_new {
    my ($client_socket) = @_;

    if ($main::user) {
        my $role = user_utils::get_role();
        if ($role ne "admin") {
            return 0;
        }
    } else {
        return 0;
    }

    my $html_content = get_admin_game_launcher_add_new::get_admin_game_launcher_add_new;
    if ($html_content) {
        return $html_content;
    }
}

sub get_admin_game_edit {
    my ($client_socket, $route) = @_;

    if ($main::user) {
        my $role = user_utils::get_role();
        if ($role ne "admin") {
            return 0;
        }
    } else {
        return 0;
    }

    my ($game_id) = $route =~ /\/admin\/gamelauncher\/edit\/(.*)/;
    print("Game ID: $game_id\n");
    if (!csharp_game::game_exists($game_id)) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("Game not found"));
        return;
    }

    my $html_content = get_admin_game_edit::get_admin_game_edit($client_socket, $game_id);
    if ($html_content) {
        return $html_content;
    }
}
1;