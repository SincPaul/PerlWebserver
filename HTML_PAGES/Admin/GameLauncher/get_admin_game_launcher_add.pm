package get_admin_game_launcher_add;

use strict;
use warnings;

use Cwd;
use JSON;

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

    my $html_body = <<HTML;

    <h1>Game Launcher</h1>
    <br>
    <h2>Add Game</h2>
    <form action="/admin/gamelauncher/add" method="post" enctype="multipart/form-data">
        <input type="text" id="name" name="game_name" required><br>
        <input type="text" id="version" name="version" required><br>
        <input type="checkbox" id="force_new_version" name="force_new_version" value="true">Force New Version (not avalailable without Server connection)<br>
        <input type="file" id="file" name="file" required><br>
        <input type="submit" value="Submit">
    </form>
    <br>
    <a href="/admin/gamelauncher">Back</a>
    <br>
HTML

    my $html_content = html_structure::get_html($html_body, "Game Launcher - Add Game");

    return ($html_content);
}

1;