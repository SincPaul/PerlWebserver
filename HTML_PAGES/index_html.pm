package index_html;


use strict;
use warnings;

sub new {
    my ($isAdminAccount) = @_;

    my $translations = language_utils::load_language("index");

    my $usercount = user_utils::get_user_count();

    # print("MAIN USER: $main::user\n");
    # print("USERCOUNT: $usercount\n");
    my $html_body = <<HTML;
    <h1>Index</h1>
    <div class="userCount">
        <h2>$translations->{userCount}</h2>
        <p>$usercount</p>
    </div>
HTML

    if (!$main::user) {
        $html_body .= <<HTML;
        <a href="/login">$translations->{login}</a><br>
        <a href="/register">$translations->{register}</a><br>
HTML
    } elsif ($main::user) {
        $html_body .= <<HTML;
        <a href="/logout">$translations->{logout}</a><br>
        <a href="/profile">$translations->{profile}</a><br>
        <a href="/profile/ploud">$translations->{ploud}</a><br>
HTML
    } 
    $html_body .= <<HTML;
    <a href="/blog">$translations->{blog}</a><br>
    <a href="/gameroom">$translations->{gameroom}</a><br>
    <a href="/calender/year">$translations->{calender}</a><br>
    <a href="/about">$translations->{about}</a><br>
    <a href="/updateLog">$translations->{updateLog}</a><br>
    <a href="/support">$translations->{support}</a><br>
    <a href="/streaming">$translations->{streaming}</a><br>
    <a href="/streaming/videos">$translations->{videos}</a><br>
    <a href="/streaming/live">$translations->{live}</a><br>
    <br>
HTML

    if ($main::user && $isAdminAccount) {
        $html_body .= <<HTML;
        <a href="/admin">$translations->{adminMenu}</a><br>
        <form action="/shutdown" method="post">
            <button type="submit">$translations->{shutdownServer}</button>
        </form>
HTML
    }
    
    $html_body .= <<HTML;
    <br>
    <br>
    <br>
    <br>
HTML

    my $html_content = html_structure::get_html($html_body, "Index");


return ($html_content);
}




1;