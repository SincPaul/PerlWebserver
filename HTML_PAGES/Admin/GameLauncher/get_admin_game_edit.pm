package get_admin_game_edit;

use strict;
use warnings;

use Cwd;
use JSON;

sub get_admin_game_edit {
    my ($client_socket, $game_id) = @_;

    if ($main::user) {
        my $role = user_utils::get_role();
        if ($role ne "admin") {
            return 0;
        }
    } else {
        return 0;
    }

    
    my $base_dir = getcwd();
    my $game_path = "$base_dir/Data/CSharpGameLauncher/Games/$game_id";
    if (!-d $game_path) {
        return 0;
    }
    my $metadata_file = "$game_path/metadata.json";
    if (!-e $metadata_file) {
        return 0;
    }
    open my $fh, '<', $metadata_file or die "Could not open file '$metadata_file' $!";
    my $metadata_text = do { local $/; <$fh> };
    close $fh;

    my $metadata = decode_json($metadata_text);
    my $version = $metadata->{version};
    my $name = $metadata->{name};
    
    my $github_link = $metadata->{github_url};
    my $access_token = $metadata->{access_token};
    my $access_token_username = $metadata->{access_token_username};
    my $access_to_source_code = $metadata->{user_access_to_source_code};

    my $html = <<HTML;
    <h2>Edit Game: "$name"</h2>
    <hr>
    <h2>Importante</h2>
    <label for="user_access_to_source_code">Should the User have Access to the Source Code:</label><br>
HTML
    if ($access_to_source_code) {
        $html .= <<HTML;
    <input type="checkbox" id="user_access_to_source_code" name="user_access_to_source_code" value="true" checked><br>
HTML
    } else {
        $html .= <<HTML;
    <input type="checkbox" id="user_access_to_source_code" name="user_access_to_source_code" value="true"><br>
HTML
    }
    $html .= <<HTML;
    <button type="button" onclick="update_user_access_to_source_code()">Update</button><br>
    <hr>
    <h2>Game Information</h2>

    <label for="game_name">Game Name:</label><br>
    <input type="text" id="game_name" name="game_name" value="$name"><br>
    <button type="button" onclick="update_game_name()">Update</button><br>

    <label for="game_version">Game Version:</label><br>
    <input type="text" id="game_version" name="game_version" value="$version"><br>
    <button type="button" onclick="update_game_version()">Update</button><br>
        
    <label for="game_file">Game File:</label><br>
    <input type="file" id="game_file" name="game_file"><br>
    <button type="button" onclick="update_game_file()">Update</button><br>

    <button type="button" onclick="delete_game()">Delete Game</button><br>

    <h3>Option 1: Upload a Bundled ZIP File</h3>
    <input type="file" id="file" name="file"><br>

    <button type="button" id="show_upload_options" onclick="uploadGameZip()">Upload Zip</button>
    <br><br>
    <button type="button" onclick="publishGameWithZip()">Start Publishing Process using Zip</button>
    <hr>
    <h3>Option 2: Use a GitHub Repository</h3>
HTML
    if ($github_link) {
        $html .= <<HTML;
    <p>
        Current GitHub Repo: <a href="$github_link">$github_link</a>
    </p>
HTML
    }
    if ($access_token_username) {
        $html .= <<HTML;
    <p>
        Access Token Username: $access_token_username
    </p>
HTML
    }
    if ($access_token) {
        $html .= <<HTML;
    <p>
        Access Token: $access_token
    </p>
HTML
    }
    $html .= <<HTML;
    <label for="github_link">GitHub Repo URL:</label>
    <input type="text" id="github_link" name="github_link" placeholder="https://github.com/user/repo.git"><br>

    <label for="access_token_username">Access Token Username (if required):</label>
    <input type="text" id="access_token_username" name="access_token_username" placeholder="Access Token Username"><br>
    <label for="access_token">Access Token (if required):</label>
    <input type="text" id="access_token" name="access_token" placeholder="Access Token"><br>

    <button type="button" id="show_upload_options" onclick="uploadGameGithub()">Upload GitHub</button>
    <br><br>
    <button type="button" onclick="publishGameWithGithub()">Start Publishing Process using Github</button>
    <hr>
    <h3>Launch Command</h3>
    <p>
        Enter the command to run the game after deployment (e.g., <code>perl aioperl.pl</code> or <code>MyApp.exe</code>).
    </p>
    <input type="text" id="launch_command" name="launch_command" placeholder="Command to run"><br>

    <button type="submit" value="Submit">Submit</button>
HTML

    my $script = <<Script;
<script>
    async function uploadGameGithub() {
        const github_link = document.getElementById('github_link').value;
        const access_token = document.getElementById('access_token').value;
        const access_token_username = document.getElementById('access_token_username').value;
        if (!github_link) {
            alert('Please enter a GitHub link!');
            return;
        }
        try {
            const response = await fetch('/admin/gamelauncher/upload/github', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    game_id: '$game_id',
                    github_link: github_link,
                    access_token: access_token,
                    access_token_username: access_token_username
                })
            });
            if (response.ok) {
                alert('Github successfully added!');
            } else {
                alert('Failed to upload game!');
            }
        } catch (error) {
            alert('Failed to upload game!');
        }
    }
    async function publishGameWithGithub() {
        try {
            const response = await fetch('/admin/gamelauncher/publish/github', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    game_id: '$game_id'
                })
            });
            if (response.ok) {
                alert('Game successfully published!');
            } else {
                alert('Failed to publish game!');
            }
        } catch (error) {
            alert('Failed to publish game!');
        }
    }
</script>
Script

    $html .= $script;

    return $html;
}

1;