package github_utils;

use strict;
use warnings;

use Cwd;

my $repo_owner = "SincPaul";
my $repo_name = "PerlWebserver";
my $branch = "main";
my $github_token = no_upload::get_github_token();

sub push_to_github {
    my ($file_path, $commit_message) = @_;
    my $base_dir = getcwd();
    my ($trimmed_filepath) = $file_path =~ /$base_dir\/(.*)/;

    # my $url = "https://api.github.com/repos/$repo_owner/$repo_name/contents/$trimmed_filepath";
    my $url = "https://api.github.com";
    # my $url = "https://wikipedia.org";

    my $headers = {
        "Authorization" => "token $github_token",
        "Accept" => "application/vnd.github+json", 
    };

    my $sha = get_current_file_sha($url, $headers, $file_path, $commit_message);

    my $body = {
        "message" => $commit_message,
        "content" => no_upload::base64_encode_file($file_path),
        "branch" => $branch,
    };
}

sub get_current_file_sha {
    my ($url, $headers, $file_path, $commit_message) = @_;

    my $port = connection_utils::get_port_from_url($url);
    my ($host, $path) = connection_utils::get_host_and_path_from_url($url);

    my $http_request = http_utils::create_http_request("GET", $host, $path, $headers);
    my $response;
    my $client_socket = $main::client_socket;
    if ($port == 443) {
        print("HTTPS REQUEST: $http_request\n");
        $response = https_utils::send_https_request($host, $port, $http_request, undef, "get_current_file_sha");
    } else {
        print("HTTP REQUEST: $http_request\n");
        $response = http_utils::send_http_request($host, $port, $http_request);
    }

    print("RESPONSE: $response\n");
    die;

    my $response_json = decode_json($response);
    my $sha = $response_json->{sha};

    return $sha;
}

sub validate_github_link {
    my ($github_url, $github_access_token) = @_;


    return 0;
    # will maybe do this later

    my ($RepoOwner, $RepoName) = $github_url =~ /https:\/\/github.com\/([^\/]+)\/([^\/]+)/;
    my $api_url = "https://api.github.com";
    my $repo_url = "$api_url/repos/$RepoOwner/$RepoName";
    # print("REPO URL: $repo_url\n");
    my $curl_command = "curl -I -s $repo_url";
    if ($github_access_token) {
        $curl_command .= " -H 'Authorization: token $github_access_token'";
    }

    # print("CURL COMMAND: $curl_command\n");

    my $response = `$curl_command`;

    if ($response =~ /^HTTP\/[\d.]+ (\d+)/) {
        # print("HTTP STATUS: $1\n");
        if ($1 == 200) {
            return 1;
        } else {
            return 0;
        }
    }
    return 0; 
}

sub pull_from_github {
    my ($github_url, $github_access_token, $github_access_token_username, $taget_dir) = @_;

    my $clone_url;

    if ($github_access_token) {
        if (!$github_access_token_username) {
            return 0;
        }
        $github_access_token =~ s/ //g;
        $github_access_token_username =~ s/ //g;
        $clone_url = "https://$github_access_token_username:$github_access_token\@github.com";
    } else {
        $clone_url = "https://github.com";
    }

    my ($RepoOwner, $RepoName) = $github_url =~ /https:\/\/github.com\/([^\/]+)\/([^\/]+)/;
    my $repo_url = "$clone_url/$RepoOwner/$RepoName.git";
    my $clone_command = "git clone $repo_url $taget_dir";
    print("CLONE COMMAND: $clone_command\n");

    my $response = `$clone_command`;

    print("RESPONSE: $response\n");

}
1;