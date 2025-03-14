package http_utils;

use strict;
use warnings;

use Socket;
use Errno qw(EPIPE);


sub send_http_response {
    my ($client_socket, $response) = @_;
    my $bytes_sent = send($client_socket, $response, 0);
    print("BYTES SENT: $bytes_sent\n");
    # print("SENT RESPONSE, CLOSING SOCKET\n");
    close($client_socket);
}

sub send_response {
    my ($client_socket, $response) = @_;
    if (!$response) {
        $response = HTTP_RESPONSE::ERROR_500("Internal Server Error");
    }
    if (!$client_socket) {
        return;
    }
    my $bytes_written = send($client_socket, $response, 0);
    if (!defined $bytes_written) {
        # noting 
    }
}
sub serve_error {
    my ($client_socket, $error) = @_;
    if (!$client_socket) {
        return;
    }
    if (!$error) {
        $error = HTTP_RESPONSE::ERROR_500("Internal Server Error");
    }
    send_response($client_socket, $error);
    close($client_socket);
}

sub encode_characters {
    my ($string) = @_;
    $string =~ s/&/&amp;/g;
    $string =~ s/</&lt;/g;
    $string =~ s/>/&gt;/g;
    $string =~ s/"/&quot;/g;
    $string =~ s/'/&#39;/g;
    return $string;
}

sub parse_input {
    my ($string) = @_;

    $string = user_utils::decode_uri($string);
    $string =~ s/\+/ /g;

    return $string;
}

sub send_http_request {
    my ($host, $port, $request) = @_;

    socket(my $socket, PF_INET, SOCK_STREAM, getprotobyname('tcp')) or die "socket: $!";
    my $ip = inet_aton($host);
    $ip = inet_ntoa($ip);
    print("IP: $ip\n");
    connect($socket, sockaddr_in($port, inet_aton($host))) or die "connect: $!";

    print("SENDING REQUEST: \n$request\n");
    send($socket, $request, 0) or die "send: $!";

    my $response = '';
    recv($socket, $response, 1024, 0) or die "recv: $!";

    print("RESPONSE: \n$response\n");
    close($socket);

    return $response;
}

sub create_http_request {
    my ($method, $host, $path, $headers, $body) = @_;

    my $http_request = <<HTTP_REQUEST;
    $method $path HTTP/1.1\r
    Host: $host\r
HTTP_REQUEST

    if ($headers) {
        foreach my $header (keys %$headers) {
            $http_request .= "    $header: $headers->{$header}\r\n";
        }
    }

    if ($body) {
        $http_request .= "Content-Length: " . length($body) . "\r\n";
        $http_request .= "\r\n";
        $http_request .= $body;
    }

    $http_request .= "\r\n";

    return $http_request;
}

1;