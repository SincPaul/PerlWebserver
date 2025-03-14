package HTTP_RESPONSE;

use strict;
use warnings;
use Digest::SHA qw(sha1);
use MIME::Base64;

sub SWITCHING_PROTOCOLS_101 {
    my ($sec_websocket_key) = @_;

    my $sec_websocket_accept = $sec_websocket_key . "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    $sec_websocket_accept = Digest::SHA->new("sha1")->add($sec_websocket_accept);
    $sec_websocket_accept = $sec_websocket_accept->digest;
    $sec_websocket_accept = encode_base64($sec_websocket_accept);
    $sec_websocket_accept =~ s/\n//g;
    
    # print("Computed Sec-WebSocket-Accept: $sec_websocket_accept\n");
    # print("SEC WEBSOCKET ACCEPT: $sec_websocket_accept\n");
    my $response = "HTTP/1.1 101 Switching Protocols\r\n"
                . "Upgrade: websocket\r\n"
                . "Connection: Upgrade\r\n"
                . "Sec-WebSocket-Accept: $sec_websocket_accept\r\n"
                . "\r\n";

    return $response;
}
sub OK {
    my ($html_content) = @_;
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 200 OK\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Connection: close\r\n";
    $response .= "Content-Length: $content_length\r\n" if $html_content;
    $response .= "\r\n";
    $response .= $html_content if $html_content;

    return $response;
}

sub OK_ACCEPT_RANGE {
    my ($video_data, $content_length, $content_type) = @_;
    # my $content_length = length($video_data);
    my $response = "HTTP/1.1 200 OK\r\n"
                . "Accept-Ranges: bytes\r\n"
                . "Content-Length: $content_length\r\n"
                . "Content-Type: $content_type\r\n"
                . "Connection: close\r\n"
                . "\r\n";

    return $response;
}

sub OK_JS_WITH_CACHE {
    my ($html_content) = @_;
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 200 OK\r\n"
                . "Content-Type: text/javascript; charset=utf-8\r\n"
                . "Connection: close\r\n"
                . "Cache-Control: public, max-age=604800\r\n"
                . "\r\n"
                . $html_content;

    return $response;
}

sub OK_FAVICON {
    my $favicon = "favicon.ico";
    open(my $fh, '<', $favicon) or die "Can't open file $favicon: $!";
    binmode $fh;
    my $content;
    {
        local $/;
        $content = <$fh>;
    }
    close($fh);

    my $response = "HTTP/1.1 200 OK\r\n";
    $response .= "Content-Type: image/x-icon\r\n";
    $response .= "Cache-Control: public, max-age=604800\r\n";
    $response .= "Content-Length: " . length($content) . "\r\n";
    $response .= "Connection: close\r\n";
    $response .= "\r\n";
    $response .= $content;

    return $response;
}

sub OK_WITH_COOKIE {
    my ($html_content, $cookie, $cookie2) = @_;
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 200 OK\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Content-Length: $content_length\r\n"
                . "Set-Cookie: $cookie; SameSite=Strict\r\n";
                if ($cookie2) {
                    $response .= "Set-Cookie: $cookie2; SameSite=Strict\r\n";
                }
                
                $response .= "Connection: close\r\n"
                . "\r\n"
                . $html_content;

    return $response;
}

sub OK_WITH_DATA {
    my ($data, $filename) = @_;
    my $content_length = length($data);
    my $response = "HTTP/1.1 200 OK\r\n"
                . "Content-Type: application/octet-stream\r\n"
                . "Content-Disposition: attachment; filename=\"$filename\"\r\n"
                . "Content-Length: " . length($data) . "\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $data;

    return $response;
}

sub OK_WITH_DATA_AND_CACHE {
    my ($data, $filename, $content_type) = @_;
    my $content_length = length($data);
    if (!$content_type) {
        $content_type = "application/octet-stream";
    }
    my $response = "HTTP/1.1 200 OK\r\n"
                . "Content-Type: $content_type\r\n"
                . "Content-Disposition: attachment; filename=\"$filename\"\r\n"
                . "Cache-Control: public, max-age=604800\r\n"
                . "X-Content-Type-Options: nosniff\r\n"
                . "Content-Length: " . length($data) . "\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $data;

    return $response;
}

sub OK_WITH_DATA_HEADER {
    my ($file_size, $filename) = @_;
    my $response = "HTTP/1.1 200 OK\r\n"
                . "Content-Type: application/octet-stream\r\n"
                . "Content-Disposition: attachment; filename=\"$filename\"\r\n"
                . "Content-Length: $file_size\r\n"
                . "Connection: close\r\n"
                . "\r\n";

    return $response;
}

sub OK_WITH_DATA_HEADER_AND_CACHE {
    my ($file_size, $filename, $content_type) = @_;
    if (!$content_type) {
        $content_type = "application/octet-stream";
    }
    my $response = "HTTP/1.1 200 OK\r\n"
                . "Content-Type: $content_type\r\n"
                . "Content-Disposition: attachment; filename=\"$filename\"\r\n"
                . "Cache-Control: inline, max-age=604800\r\n"
                . "Content-Length: $file_size\r\n"
                . "Connection: close\r\n"
                . "\r\n";

    return $response;
}

sub NO_MORE_CONTENT_204 {
    my $response = "HTTP/1.1 204 No Content\r\n"
                . "Connection: close\r\n"
                . "\r\n";

    return $response;
}

sub PARTIAL_CONTENT_206 {
    my ($data, $start_range, $end_range, $file_size, $content_type) = @_;
    my $content_length = length($data);
    my $response = "HTTP/1.1 206 Partial Content\r\n"
                . "Content-Type: $content_type\r\n"
                . "Content-Length: " . length($data) . "\r\n"
                . "X-Content-Type-Options: nosniff\r\n"
                . "Content-Range: bytes $start_range-$end_range/$file_size\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $data;

    return $response;
}

sub PARTIAL_CONTENT_206_NO_CONTENT_RANGE {
    my ($file_size, $content_type) = @_;
    my $response = "HTTP/1.1 206 Partial Content\r\n"
                . "Content-Type: $content_type\r\n"
                . "Content-Length: $file_size\r\n"
                . "X-Content-Type-Options: nosniff\r\n"
                . "Connection: close\r\n"
                . "\r\n";

    return $response;
}

sub REDIRECT_303 { 
    my ($location) = @_;
    my $response = "HTTP/1.1 303 See Other\r\n"
                . "Location: $location\r\n"
                . "Connection: close\r\n"
                . "\r\n";

    return $response;
}

sub REDIRECT_303_WITH_COOKIE { 
    my ($location, $cookie, $cookie2) = @_;
    my $response = "HTTP/1.1 303 See Other\r\n"
                . "Location: $location\r\n"
                . "Set-Cookie: $cookie; SameSite=Strict\r\n";
                if ($cookie2) {
                    $response .= "Set-Cookie: $cookie2; SameSite=Strict\r\n";
                }

                $response .= "Connection: close\r\n"
                . "\r\n";

    return $response;
}

sub REDIRECT_303_WITH_DATA {
    my ($location, $data, $filename) = @_;
    my $response = "HTTP/1.1 303 See Other\r\n"
                . "Location: $location\r\n"
                . "Content-Type: application/octet-stream\r\n"
                . "Content-Disposition: attachment; filename=\"$filename\"\r\n"
                . "Content-Length: " . length($data) . "\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $data;

    return $response;
}

sub ERROR_400 {
    my ($additional_info) = @_;
    my $html_content = "<h1>400 Bad Request</h1>";
    if ($additional_info) {
        $html_content .= "<p>$additional_info</p>";
    }
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 400 Bad Request\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Content-Length: $content_length\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $html_content;

    return $response;
}

sub ERROR_400_WEBSOCKET_VERSION {
    my ($supported_version) = @_;

    my $response = "HTTP/1.1 400 Bad Request\r\n"
                . "Sec-WebSocket-Version: $supported_version\r\n"
                . "Connection: close\r\n"
                . "\r\n";

    return $response;
}

sub ERROR_401 {
    my ($additional_info) = @_;
    # print("SENDING 401\n");
    my $html_content = "<h1>401 Unauthorized</h1>";
    if ($additional_info) {
        $html_content .= "<p>$additional_info</p>";
    }
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 401 Unauthorized\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Content-Length: $content_length\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $html_content;

    return $response;
}

sub ERROR_401_WITH_COOKIE {
    my ($additional_info, $cookie) = @_;
    # print("SENDING 401 WITH COOKIE\n");
    my $html_content = "<h1>401 Unauthorized</h1>";
    if ($additional_info) {
        $html_content .= "<p>$additional_info</p>";
    }
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 401 Unauthorized\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Set-Cookie: $cookie; SameSite=Strict\r\n"
                . "Content-Length: $content_length\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $html_content;

    return $response;
}

sub ERROR_404 {
    my ($additional_info) = @_;
    # print("SENDING 404\n");
    my $html_content = "<h1>404 Not Found</h1>";
    if ($additional_info) {
        $html_content .= "<p>$additional_info</p>";
    }
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 404 Not Found\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Content-Length: $content_length\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $html_content;

    return $response;
}

sub ERROR_404_WITH_COOKIE {
    my ($html_content, $cookie) = @_;
    # print("SENDING 404 WITH COOKIE\n");
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 404 Not Found\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Set-Cookie: $cookie; SameSite=Strict\r\n"
                . "Content-Length: $content_length\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $html_content;

    return $response;
}

sub ERROR_405 {
    my $html_content = "<h1>405 Method Not Allowed</h1>";
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 405 Method Not Allowed\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Content-Length: $content_length\r\n"
                . "Allow: GET, POST\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $html_content;

    
    return $response;
}

sub ERROR_409 {
    my ($additional_info) = @_;
    my $html_content = "<h1>409 Conflict</h1>";
    if ($additional_info) {
        $html_content .= "<p>$additional_info</p>";
    }
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 409 Conflict\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Content-Length: $content_length\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $html_content;

    return $response;
}

sub ERROR_413 {
    my ($additional_info) = @_;
    my $html_content = "<h1>413 Payload Too Large</h1>";
    if ($additional_info) {
        $html_content .= "<p>$additional_info</p>";
    }
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 413 Payload Too Large\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Content-Length: $content_length\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $html_content;

    return $response;
}

sub ERROR_500 {
    my ($additional_info) = @_;
    my $html_content = "<h1>500 Internal Server Error</h1>";
    if ($additional_info) {
        $html_content .= "<p>$additional_info</p>";
    }
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 500 Internal Server Error\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Content-Length: $content_length\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $html_content;

    return $response;
}

sub ERROR_501 {
    my $html_content = "<h1>501 Not Implemented</h1>";
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 501 Not Implemented\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Content-Length: $content_length\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $html_content;

    return $response;
}

sub ERROR_505 {
    my $html_content = "<h1>505 HTTP Version Not Supported</h1>";
    my $content_length = length($html_content);
    my $response = "HTTP/1.1 505 HTTP Version Not Supported\r\n"
                . "Content-Type: text/html; charset=utf-8\r\n"
                . "Content-Length: $content_length\r\n"
                . "Connection: close\r\n"
                . "\r\n"
                . $html_content;

    return $response;
}


1;