package connection_utils;

use strict;
use warnings;

sub get_client_data {
    my ($client_fd, $client_socket) = @_;
    # print("HELLOOOOOO\n");

    if ($epoll::clients{$client_fd}{"tries"} && $epoll::clients{$client_fd}{"tries"} > 10) {
        main::remove_client_complete($client_fd);
        return;
    }

    my $buffer;

    recv($client_socket, $buffer, 1024, 0);

    my $request = $buffer;
    # print("REQUEST: $request\n");
    my $session_cookie = request_utils::get_session_cookie($buffer);
    # print("SESSION COOKIE: $session_cookie\n");
    my ($uuid, $session_id) = cookie_utils::validate_session($session_cookie);
    # print("UUID: $uuid\n");
    # print("SESSION ID: $session_id\n");

    if ($uuid) {
        if(!user_utils::exist_not_banned($client_socket, $uuid)) {
            return;
        }
        user_utils::populate_user($session_cookie);
        $epoll::clients{$client_fd}{main_user} = $main::user;
    }

    if ($request =~ /Content-Length: (\d+)/) {
        $epoll::clients{$client_fd}{"content_length"} = $1;
    }
    if ($request =~ /Sec-WebSocket-Key: (.*)\r\n/) {
        # print("WEBSOCKET REQUEST1\n");
        websocket_utils::handle_websocket_request($client_socket, $request);
        return;
    }
    if (length($buffer) < 1024) {
        $epoll::clients{$client_fd}{"more"} = 0;
    }
    if ($request =~ /\r\n\r\n/) {
        my ($header, $body) = split(/\r\n\r\n/, $request, 2);
        my $content_length = $epoll::clients{$client_fd}{"content_length"};
        my $bytes_read = length($body);
        $epoll::clients{$client_fd}{"header"} = $header;
        if ($header =~ /Content-Type: multipart\/form-data; boundary=(.*)\r\n/) {
            $epoll::clients{$client_fd}{"boundary"} = $1;
            $epoll::clients{$client_fd}{"is_upload"} = 1;
            my $referer = request_utils::get_referer($header);
            $epoll::clients{$client_fd}{"referer"} = $referer;
            ($epoll::clients{$client_fd}{"location"}) = $header =~ /POST (.*) HTTP/;
        }
        # $epoll::clients{$client_fd}{"body"} = $body;
        $epoll::clients{$client_fd}{"bytes_read"} = $bytes_read;
        $epoll::clients{$client_fd}{"content_length"} = $content_length;
        my $temp_file = "/tmp/request_body_$client_fd";
        open(my $fh, ">", $temp_file) || die "Can't open temp file: $!";
        print $fh $body;
        close $fh;
        $epoll::clients{$client_fd}{"temp_file"} = $temp_file;
    
        
        # my $session_cookie = request_utils::get_session_cookie($header);
        # my $uuid;
        # my $session_id;
        # if ($session_cookie) {
        #     ($uuid, $session_id) = cookie_utils::validate_session($session_cookie);
            # print("UUID1: $uuid\n");
        # }

        if ($content_length) {
            # print("CONTENT LENGTH: $content_length\n");
            # print("MAX STORAGE: $main::max_storage\n");

            if ($uuid) {
                my $max_storage = user_utils::get_user_max_storage($uuid);
                my $max_file_size = $max_storage;
                if ($epoll::clients{$client_fd}{"location"} && $epoll::clients{$client_fd}{"location"} =~ /profile\/ploud/) {
                    $max_file_size = $max_storage - user_utils::get_current_used_storage($uuid);
                }
                # print("MAX FILE SIZE: $max_file_size\n");
                # print("MAX STORAGE: $max_storage\n");
                # my $max_server_size = user_utils::get_max_server_size();
                # if ($max_file_size > $max_server_size * $server::storage_bottleneck) {
                    # print("SERVER STORAGE EXCEEDED\n");
                #     http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_413("Server storage exceeded"));
                #     return;
                # }
                if ($content_length > $max_file_size && !$main::user->{"role"} eq "admin") {
                    print("File too large\n");

                    print("CURRENT USED STORAGE: ".user_utils::get_current_used_storage($uuid)."\n");
                    print("MAX FILE SIZE: $max_file_size\n");
                    print("CONTENT LENGTH: $content_length\n");
                    http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_413("File too large"));
                    return;
                }
                my $server_storage = user_utils::get_server_storage();
                my $free_server_storage = $server_storage->{"free"};
                if ($content_length > $free_server_storage) {
                    print("Server storage exceeded\n");
                    http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_413("Server storage exceeded"));
                    return;
                }
            }
        }
    } else {
        $epoll::clients{$client_fd}{"message"} = $request;
        # print("MESSAGE: $request\n");
        if (!$epoll::clients{$client_fd}{"is_ws"}) {
            # print("ADDING TO TRIES\n");
            $epoll::clients{$client_fd}{"tries"}++;
        }
    }
    # print("FINITO GETTING DATA\n");
}

sub handle_client_data {
    my ($client_fd, $client_socket) = @_;

    my $buffer;
    # print("HANDLE CLIENT DATA\n");

    if ($epoll::clients{$client_fd}{"content_length"} && $epoll::clients{$client_fd}{"bytes_read"} < $epoll::clients{$client_fd}{"content_length"}) {
        recv($client_socket, $buffer, 1024, 0);
        # $epoll::clients{$client_fd}{"body"} .= $buffer;
        $epoll::clients{$client_fd}{"bytes_read"} += length($buffer);

        my $temp_file = $epoll::clients{$client_fd}{"temp_file"};
        if (!$temp_file) {
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_500("Internal server error"));
            main::remove_client($client_fd);
            return;
        }
        # print("Writing to temp file: $temp_file\n");
        open(my $fh, ">>", $temp_file) || die "Can't open temp file: $!";
        print $fh $buffer;
        close $fh;

        # $epoll::clients{$client_fd}{"request"} .= $buffer;
        # print("+ ".length($buffer)."\n");
        # print("BYTES READ: $epoll::clients{$client_fd}{bytes_read}\n");
        # print("CONTENT LENGTH: $epoll::clients{$client_fd}{content_length}\n");
        if ($epoll::clients{$client_fd}{"bytes_read"} >= $epoll::clients{$client_fd}{"content_length"}) {
            # print("FINISHED READING REQUEST\n");
            main::handle_normal_request($client_fd, $epoll::clients{$client_fd}{"temp_file"});
            main::remove_client_in($client_fd);
            # epoll_ctl($epoll, EPOLL_CTL_DEL, $client_fd, 0) >= 0 || die "Can't remove client socket from epoll: $!";
            # close($client_socket);
            # delete $epoll::clients{$client_fd};
        }
    } else {
        # print("REQUEST: $epoll::clients{$client_fd}{request}\n");
        # print("FINItO REQUEST\n");
        main::handle_normal_request($client_fd, $epoll::clients{$client_fd}{temp_file});
        main::remove_client_in($client_fd);
        # epoll_ctl($epoll, EPOLL_CTL_DEL, $client_fd, 0) >= 0 || die "Can't remove client socket from epoll: $!";
        # close($client_socket);
        # delete $epoll::clients{$client_fd};
    }
}

sub read_temp_file {
    my ($temp_file, $index) = @_;
    my $chunksize = 1024;

    open(my $fh, "<", $temp_file) or do {
        warn "Can't open temp file: $!";
        return;
    };

    seek($fh, $index * $chunksize, 0) or do {
        warn "Can't seek in temp file: $!";
        close $fh;
        return;
    };

    my $next_chunk;
    read $fh, $next_chunk, $chunksize;
    close $fh;
    return $next_chunk;
}

sub get_port_from_url {
    my ($url) = @_;

    my ($protocol, $host) = $url =~ /^(?:(\w+):\/\/)?([^:\/]+)/;

    my $port;
    if ($protocol && $protocol eq "http") {
        $port = 80;
    } elsif ($protocol && $protocol eq "https") {
        $port = 443;
    } else {
        ($host, $port) = get_port_from_host($host);
    }

    if (!$port) {
        $port = 80;
    }

    return $port;
}

sub get_host_and_path_from_url {
    my ($url) = @_;

    my ($host, $path) = $url =~ /^(?:.*:\/\/)?([^:\/]+)(?::\d+)?(\/.*)?$/;
    $path ||= '/';
    
    return ($host, $path);
}

sub get_port_from_host {
    my ($host) = @_;
    my $port;
    if ($host =~ /(.*):(\d+)$/) {
        $port = $1;
    }
    return ($host, $port);
}

sub get_server_ip {
    my $ifconfig_output = `ifconfig`;
    my @interfaces = split(/\n\n/, $ifconfig_output);
    foreach my $interface (@interfaces) {
        if ($interface =~ /^(.*?):\sflags=(?:.*)inet (.*?)\s/s) {
            if ($1 =~ /lo/ && $2 == 127.0.0.1 || $1 =~ /docker/) {
                next;
            }
            return $2;
        }
    }

    return;
}
1;