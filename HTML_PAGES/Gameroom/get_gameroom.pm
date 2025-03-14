package get_gameroom;

use strict;
use warnings;

sub get_gameroom {

    my $translations = language_utils::load_language("gameroom");

    my $html = <<HTML;
    <h1>Game Room</h1>
    <br>
HTML
    $html .= html_utils::get_game_online_status($translations);

    $html .= <<HTML;
    <br>
    <div class="game_buttons">
        <a href="/gameroom/memory">$translations->{memory}</a>
    </div>
    <br>
    <br>
    <div class="game_launcher">
        <a href="/gamelauncher/download/launcher">$translations->{game_launcher} Download</a>
    </div>
HTML
    

    $html .= html_utils::create_breadcrumbs("gameroom");

    my $html_content = html_structure::get_html($html, "Game Room");

    return $html_content;
}

1;