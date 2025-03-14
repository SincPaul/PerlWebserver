package get_admin_game_launcher_add_new;

use strict;
use warnings;

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

    my $html_body = <<HTML;

    <h1>Game Launcher</h1>
<br>
<h2>Add Game</h2>

<label for="name">Game Name:</label>
<input type="text" id="name" name="game_name" required><br>

<label for="version">Version:</label>
<input type="text" id="version" name="version" required><br>

<input type="checkbox" id="force_new_version" name="force_new_version" value="true">
<label for="force_new_version">Force New Version (not available without Server connection)</label><br>

<button type="button" id="show_upload_options" onclick="initializeGame()">Initialize Game</button>
<hr>
    
<br>
<a href="/admin/gamelauncher">Back</a>
HTML

    my $script = <<Script;
<script>
    async function initializeGame() {
        fetch('/admin/gamelauncher/initialize', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                game_name: document.getElementById('name').value,
                game_version: document.getElementById('version').value,
                force_new_version: document.getElementById('force_new_version').checked
            })
        }).then(async response => {
            if (response.ok) {
                alert('Game initialized successfully!');
                const data = await response.json();
                console.log(data);
                alert('Game ID: ' + data.game_id);
                window.location.href = '/admin/gamelauncher/edit/' + data.game_id;
            } else {
                alert('Failed to initialize game!');
            }
        });
    }
</script>
Script

    $html_body .= $script;


    my $html_content = html_structure::get_html($html_body, "Game Launcher - Add Game");

    return ($html_content);
}

1;