package get_admin_game_launcher_html;

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

    my $base_dir = getcwd();
    my $csharp_launcher_path = ("$base_dir/Data/CSharpGameLauncher");
    if (!-d $csharp_launcher_path) {
        mkdir $csharp_launcher_path;
    }
    my $csharp_game_path = "$csharp_launcher_path/Games";
    if (!-d $csharp_game_path) {
        mkdir $csharp_game_path;
    }
    my $gamelist_file = "$csharp_game_path/gamelist.json";
    if (!-e $gamelist_file) {
        open my $fh, '>', $gamelist_file or die "Could not open file '$gamelist_file' $!";
        print $fh "{}";
        close $fh;
    }
    open my $fh, '<', $gamelist_file or die "Could not open file '$gamelist_file' $!";
    my $json_text = do { local $/; <$fh> };
    close $fh;
    my $json = decode_json($json_text);
    my @games;
    foreach my $game_id (keys %$json) {
        my $game_path = "$csharp_game_path/$game_id";
        if (!-d $game_path) {
            mkdir $game_path;
        }
        my $metadata_file = "$game_path/metadata.json";
        if (!-e $metadata_file) {
            open my $fh, '>', $metadata_file or die "Could not open file '$metadata_file' $!";
            print $fh "{}";
            close $fh;
        }
        open my $fh, '<', $metadata_file or die "Could not open file '$metadata_file' $!";
        my $metadata_text = do { local $/; <$fh> };
        close $fh;
        my $metadata = decode_json($metadata_text);
        my $version = $metadata->{version};
        my $name = $metadata->{name};
        my $hash = $metadata->{hash};
        my %game = (
            id => $game_id,
            name => $name,
            version => $version,
            hash => $hash
        );
        push @games, \%game;
    }
    
    my $html_body = <<HTML;
    <h1>Game Launcher</h1>
    <br>
    <a href="/admin/gamelauncher/add">Add a New Game</a>
    <a href="/admin/gamelauncher/add/new">Add a New Game, but better</a>
    <br>
    <br>
    <table>
        <tr>
            <th>ID</th>
            <th>Name</th>
            <th>Version</th>
            <th>Hash</th>
            <th>Actions</th>
        </tr>
HTML
    foreach my $game (@games) {
        my $id = $game->{id};
        my $name = $game->{name};
        my $version = $game->{version};
        my $hash = $game->{hash};
        $html_body .= <<HTML;
        <tr>
            <td>$id</td>
            <td>$name</td>
            <td>$version</td>
            <td>$hash</td>
            <td>
                <a href="/admin/gamelauncher/show/$id">Show</a>
            </td>
        </tr>
HTML
    }
    $html_body .= <<HTML;
    </table>
    <br>
    <span class="inline_buttons">
        <a href="/admin">Return to Admin</a>
    </span>
    <br>
HTML

    my $html_content = html_structure::get_html($html_body, "Game Launcher");

    return ($html_content);   
}

1;