package admin_html;

use strict;
use warnings;

sub get_admin {
    if ($main::user) {
        my $role = user_utils::get_role();
        if ($role ne "admin") {
            return 0;
        }
    } else {
        return 0;
    }

    my $html_body = <<HTML;

    <h1>Admin</h1>
    <br>
    <a href="/admin/users">Users</a>
    <a href="/admin/updateLog">Update Log</a>
    <a href="/admin/gamelauncher">Game Launcher</a>
    <span class="inline_buttons">
        <a href="/logout">Logout</a>
        <a href="/ ">Return to index</a>
    </span>
    <br>
HTML

    my $html_content = html_structure::get_html($html_body, "Admin");



    return ($html_content);
}

1;