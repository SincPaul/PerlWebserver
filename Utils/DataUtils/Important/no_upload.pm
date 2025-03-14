package no_upload;

use strict;
use warnings;

use Cwd;
use JSON;

sub get_cookie_encryption_key {
    my $base_dir = getcwd();
    my $key_file = "$base_dir/Data/Private/cookie_encryption_key.txt";

    open my $fh, "<", $key_file or do {
        return;
    };
    my $key = do { local $/; <$fh> };
    close $fh;

    return $key;
}

sub get_srs_secret_key {
    my $base_dir = getcwd();
    my $key_file = "$base_dir/Data/Private/srs_secret_key.txt";

    open my $fh, "<", $key_file or do {
        return;
    };
    my $key = do { local $/; <$fh> };
    close $fh;

    return $key;
}

sub get_google_app_password {
    my $base_dir = getcwd();
    my $pw_file = "$base_dir/Data/Private/google_app_password.txt";

    open my $fh, "<", $pw_file or do {
        return;
    };
    my $pw = do { local $/; <$fh> };
    close $fh;

    return $pw;
}

sub get_github_token {
    my $base_dir = getcwd();
    my $token_file = "$base_dir/Data/Private/github_token.txt";

    open my $fh, "<", $token_file or do {
        return;
    };
    my $token = do { local $/; <$fh> };
    close $fh;

    return $token;
}

sub get_chat_db {
    my $base_dir = getcwd();
    my $db_file = "$base_dir/Data/Private/chat_db.json";

    open my $fh, "<", $db_file or do {
        return;
    };
    my $db = do { local $/; <$fh> };
    close $fh;

    my $data = decode_json($db);
    print("DATA: $data\n");

    return $data;
    #{
    #   "name": "",
    #   "host": "",
    #   "port": "",
    #   "user": "",
    #   "password": ""
    #}
}
1;