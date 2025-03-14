package https_utils;

use strict;
use warnings;

use Socket;
use IO::Epoll;
use bigint;
use Crypt::GCM;
use Crypt::Cipher::AES;
use Digest::SHA qw(hmac_sha256);

my %record_layer_structure = (
    "handshake" => 22,
);

my %handshake_structure = (
    "client_hello" => 1,
    "server_hello" => 2,
    "finished" => 20,
);


sub send_https_request {
    my ($host, $port, $request, $client_socket, $caller) = @_;

    my $client_fd;
    if ($client_socket) {
        $client_fd = fileno($client_socket);
    }
    $epoll::clients{$client_fd}{tls}{host} = $host;
    $epoll::clients{$client_fd}{tls}{port} = $port;
    $epoll::clients{$client_fd}{tls}{request} = $request;

    if (!$epoll::clients{$client_fd}{is_tls} == 1 || !$epoll::clients{$client_fd}{tls}{tls_status} == 10) {
        $epoll::clients{$client_fd}{tls}{im_client} = 1;
        print("IM CLIENT\n");
        print("CLIENT SOCKET: $client_socket\n");
        handle_tls_handshake($client_socket, $host, $port, $caller, $request);
        return;
    }

    my $socket = establish_tls_connection($host, $port);
    my $encrypted_request = encrypt_request($request, $socket);
    send($socket, $encrypted_request, 0) or die "send: $!";

    recv($socket, my $response, 1024, 0) or die "recv: $!";
    my $decrypted_response = decrypt_response($response, $socket);

    close($socket);

    return $response;
}

my %tls_handshake_status = (
    1 => \&handle_client_hello,
    2 => \&handle_server_hello,
    3 => \&handle_certificate,
    4 => \&handle_server_key_exchange,
    5 => \&handle_certificate_request,
    6 => \&handle_server_hello_done,
    7 => \&handle_certificate_verify,
    8 => \&handle_client_key_exchange,
    9 => \&handle_finished,
);

sub handle_tls {
    my ($client_socket) = @_;

    if (!$client_socket) {
        $client_socket = $main::client_socket;
    }
    print("Client Socket: $client_socket\n");
    my $client_fd = fileno($client_socket);
    if (!$epoll::clients{$client_fd}{is_tls}) {
        return;
    }

    my $tls_status = $epoll::clients{$client_fd}{tls}{tls_status};
    if ($tls_status == 10) {
        #! fertig mit handshake, verbindung aufgebaut, nachrichten empfangen/senden
        print("RECIEVE REQUEST\n");
        receive_request($client_socket);
    }

    if ($epoll::clients{$client_fd}{tls}{im_client} && $epoll::clients{$client_fd}{tls}{im_client} == 1) {
        handle_tls_handshake($client_socket);
    } else {
        handle_tls_handshake_from_client($client_socket, $epoll::clients{$client_fd}{tls}{host});
    }
}

sub receive_request {
    my ($client_socket) = @_;

    my $client_fd = fileno($client_socket);
    my $response;
    recv($client_socket, $response, 1024, 0);
    my $temp_file;
    if (length($response) < 1024) {
        print("DONE READING");
        $temp_file = "/tmp/$client_fd" . "_https_response";
        $epoll::clients{$client_fd}{tls}{temp_file} = $temp_file;
        open my $fh, ">", $temp_file or die "Cannot open $temp_file: $!";
        binmode $fh;
        print $fh $response;
        close $fh;
        decrypt_https_response($client_socket, $temp_file);
    } else {
        print("READING MORE");
        if ($epoll::clients{$client_fd}{tls}{https_temp_file}) {
            $temp_file = $epoll::clients{$client_fd}{tls}{temp_file};
        } else {
            $temp_file = "/tmp/$client_fd" . "_https_response";
            $epoll::clients{$client_fd}{tls}{temp_file} = $temp_file;
            open my $fh, ">", $temp_file or die "Cannot open $temp_file: $!";
            close $fh;
        }
        open my $fh, ">>", $temp_file or die "Cannot open $temp_file: $!";
        binmode $fh;
        print $fh $response;
        close $fh;
        main::epoll_loop();
    }
}

sub decrypt_https_response {
    my ($client_socket, $temp_file) = @_;

    my $client_fd = fileno($client_socket);
    my $file_size = -s $temp_file;
    print("FILE SIZE: $file_size\n");
    open my $fh, '<', $temp_file or die "Cannot open $temp_file: $!";
    binmode $fh;
    my $response = do { local $/; <$fh> };
    close $fh;
    my $request_data = $response;
    
    # my $key = create_traffic_key();
    # die;
    my $key = $epoll::clients{$client_fd}{tls}{application_write_key}->{server_key};
    my $iv = $epoll::clients{$client_fd}{tls}{application_write_key}->{server_iv};
    my $record_sequence_number = 1;#$epoll::clients{$client_fd}{tls}{server_record_counter};
    print("KEY: " . unpack("H*", $key) . "\n");
    print("IV: " . unpack("H*", $iv) . "\n");
    print("RECORD SEQUENCE NUMBER: $record_sequence_number\n");
    my $decrypted_data = decrypt_data($request_data, $key, $iv, $record_sequence_number);
    print("DECRYPTED DATA: " . unpack("H*", $decrypted_data) . "\n");
    die;
}

sub create_traffic_key {
    my $client_fd = fileno($main::client_socket);
    my $last_key = $epoll::clients{$client_fd}{tls}{last_key};
    # return $last_key;
    my $key = hkdf_expand_label($last_key, "traffic udp", "", 32, 1);
    $epoll::clients{$client_fd}{tls}{last_key} = $key;
    return $key;
}

sub handle_tls_handshake {
    my ($client_socket, $host, $port, $caller, $request) = @_;

    my $client_fd;
    print("Client Socket: $client_socket\n");
    if (!$client_socket) {
        print("NO CLIENT SOCKET\n");
        $client_socket = create_socket_connection($host, $port);
        $main::client_socket = $client_socket;
        print("Client Socket: $client_socket\n");
        $client_fd = fileno($client_socket);
        print("Client FD: $client_fd\n");
        $epoll::clients{$client_fd}{is_tls} = 1;
        $epoll::clients{$client_fd}{tls}{caller} = $caller;
        $epoll::clients{$client_fd}{tls}{request} = $request;
    } else {
        $client_fd = fileno($client_socket);
    }

    
    my $tls_status = $epoll::clients{$client_fd}{tls}{tls_status};
    if (!$host) {
        $host = $epoll::clients{$client_fd}{tls}{host};
    } else {
        $epoll::clients{$client_fd}{tls}{host} = $host;
    }


    if (!$tls_handshake_status{$tls_status}) {
        $epoll::clients{$client_fd}{is_tls} = 1;
        $epoll::clients{$client_fd}{tls}{tls_status} = 1;
        $tls_status = 1;
    }

    print("TLS STATUS: $tls_status\n");
    $tls_handshake_status{$tls_status}->($client_socket, $host);
}

sub create_socket_connection {
    my ($host, $port) = @_;
    print("HOST: $host\n");
    print("PORT: $port\n");
    my $ip = gethostbyname($host);
    $ip = inet_ntoa($ip);
    print("IP: $ip\n");
    socket(my $socket, PF_INET, SOCK_STREAM, getprotobyname('tcp')) or die "socket: $!";
    connect($socket, sockaddr_in($port, inet_aton($host))) or die "connect: $!";
    epoll_ctl($main::epoll, EPOLL_CTL_ADD, fileno($socket), EPOLLIN) >= 0 || die "Can't add client socket to epoll: $!";
    my $client_fd = fileno($socket);
    $epoll::clients{$client_fd}{"socket"} = $socket;
    $epoll::clients{$client_fd}{tls}{im_client} = 1;
    print("ADDED CLIENT SOCKET TO EPOLL\n");
    return $socket;
}

sub handle_client_hello {
    my $client_socket = $main::client_socket;
    print("Client SOcket: $client_socket\n");
    my $host = $epoll::clients{fileno($client_socket)}{tls}{host};
    print("HANDLE CLIENT HELLO\n");
    my $client_random = generate_client_random() or die "Cannot generate client random";
    my $client_hello = create_client_hello($client_random, $host);
    # die;
    # #! test vector
    # my $client_hello = pack("H*", "16030100c4010000c00303d4b9503c5e95c9eecc99ce6376ccad4dcc06d7c8f1fa44b0d95600e9a0586c67000006130113031302010000910000000b0009000006736572766572ff01000100000a00140012001d0017001800190100010101020103010400230000003300260024001d0020b0f5019fb0f1e5376b8b1dfb905f1d915161bac37707dad8907bd71b9807b345002b0003020304000d0020001e040305030603020308040805080604010501060102010402050206020202002d00020101001c00024001");
    # my $client_hello_payload =   pack("H*", "010000c00303d4b9503c5e95c9eecc99ce6376ccad4dcc06d7c8f1fa44b0d95600e9a0586c67000006130113031302010000910000000b0009000006736572766572ff01000100000a00140012001d0017001800190100010101020103010400230000003300260024001d0020b0f5019fb0f1e5376b8b1dfb905f1d915161bac37707dad8907bd71b9807b345002b0003020304000d0020001e040305030603020308040805080604010501060102010402050206020202002d00020101001c00024001");
    $epoll::clients{fileno($client_socket)}{tls}{client_random} = $client_random;
    # $epoll::clients{fileno($client_socket)}{tls}{client_hello} = $client_hello_payload;
    # $epoll::clients{fileno($client_socket)}{tls}{client_hello} = $client_hello;
    $epoll::clients{fileno($client_socket)}{tls}{tls_status} = 2;
    send($client_socket, $client_hello, 0) or die "send: $!";
    print("DONT WITH CLIENT HELLO, WAITING FOR SERVER HELLO\n");
    main::epoll_loop();
}

sub handle_server_hello {
    my $client_socket = $main::client_socket;
    my $client_fd = fileno($client_socket);
    print("HANDLING SERVER HELLO\n");
    if ($epoll::clients{$client_fd}{tls}{tls_status} != 2) {
        return;
    }

    if (!$epoll::clients{$client_fd}{tls}{tls_state}{2}{finished_reading} == 1) {
        recv($client_socket, my $response, 1024, 0);
        # print("RESPONSE: $response\n");
        my $temp_file; 
        if ($epoll::clients{$client_fd}{tls}{tls_state}{2}{temp_file}) {
            $temp_file = $epoll::clients{$client_fd}{tls}{tls_state}{2}{temp_file};
        } else {
            $temp_file = "/tmp/$client_fd" . "_server_hello";
            $epoll::clients{$client_fd}{tls}{tls_state}{2}{temp_file} = $temp_file;
            open(my $fh, ">", $temp_file) or die "Cannot open $temp_file: $!";
            close $fh;
        }

        open(my $fh, ">>", $temp_file) or die "Cannot open $temp_file: $!";
        binmode $fh;
        print $fh $response;
        close $fh;
        if (length($response) < 1024) {
            print("DONE READING SERVER HELLO\n");
            $epoll::clients{$client_fd}{tls}{tls_state}{2}{finished_reading} = 1;
        } else {
            print("READING MORE SERVER HELLO\n");
            main::epoll_loop();
        }
    }

    my $temp_file = "/tmp/$client_fd" . "_server_hello";
    my $file_size = -s $temp_file;
    print("FILE SIZE: $file_size\n");
    if ($file_size > 1024*1024) {
        #! CLOSE CONNECTION
    }
    open my $fh, '<', $temp_file or die "Cannot open $temp_file: $!";
    binmode $fh;
    my $response = do { local $/; <$fh> };
    close $fh;
    my $request_data = $response;
    my $full_size = length($request_data);
    my $offset = 0;
    while($epoll::clients{$client_fd}{tls}{tls_state}{2}{finished_parsing} != 1) {
        $offset = parse_tls_record($request_data, $client_socket, $offset);
        if ($offset >= $full_size) {
            print("OFFSET: $offset\n");
            print("FULL SIZE: $full_size\n");
            $epoll::clients{$client_fd}{tls}{tls_state}{2}{finished_parsing} = 1;
        }
    }

    print("DONE PARSING SERVER HELLO\n");
    my $shared_secret = calculate_shared_secret($client_socket);
    my $encryption_key = calculate_handshake_encryption_key($shared_secret);
    
    my $final_encryption_key = calculate_appliation_traffic_encryption_key($client_socket, $encryption_key);

    send_encrypted_request($client_socket, $final_encryption_key, $epoll::clients{$client_fd}{tls}{request});
    
    $epoll::clients{$client_fd}{tls}{tls_status} = 10;
    main::epoll_loop();
}

sub send_encrypted_request {
    my ($client_socket, $encryption_key, $request) = @_;

    my $client_fd = fileno($client_socket);

    my $record_sequence_number = $epoll::clients{$client_fd}{tls}{client_record_counter};
    if (!$record_sequence_number) {
        $record_sequence_number = 0;
    }
    
    my $static_server_write_iv = $epoll::clients{$client_fd}{tls}{application_write_key}->{server_iv};
    my $nonce = compute_nonce($record_sequence_number, $static_server_write_iv);

    my $server_write_key = $encryption_key->{server_key};
    my $additional_data = pack("C", 23) . pack("n", 0x0303) . pack("n", length($request));

    my $tag_length = 16;
    my ($ciphertext, $tag) = AEAD_encrypt($server_write_key, $nonce, $additional_data, $request, $tag_length);
    
    my $encrypted_data = $ciphertext . $tag;

    print("Encrypted request: " . unpack("H*", $encrypted_data) . "\n");

    $epoll::clients{$client_fd}{tls}{record_sequence_number}++;

    send($client_socket, $encrypted_data, 0) or die "send: $!";
}

sub create_ciphers {
    my ($client_socket, $encryption_key) = @_;

    my $cipher_suite = $epoll::clients{fileno($client_socket)}{tls}{cipher_suite};
    my $client_key = $encryption_key->{client_key};
    my $client_iv = $encryption_key->{client_iv};
    my $server_key = $encryption_key->{server_key};
    my $server_iv = $encryption_key->{server_iv};

    my $client_cipher = Crypt::GCM->new(-key => $client_key, -cipher => 'Crypt::Cipher::AES');
    $client_cipher->set_iv($client_iv);

    my $server_cipher = Crypt::GCM->new(-key => $server_key, -cipher => 'Crypt::Cipher::AES');
    $server_cipher->set_iv($server_iv);

    $epoll::clients{fileno($client_socket)}{tls}{ciphers} = {
        "client_cipher" => $client_cipher,
        "server_cipher" => $server_cipher,
    };
}

sub calculate_shared_secret {
    my ($client_socket) = @_;

    my $private_key = $epoll::clients{fileno($client_socket)}{tls}{private_key};
    #! test
    # my $private_key = pack("H*", "0161d7bf4ba06c3568f10954f0f1ca087460549cdc7bfeb2776b4604d82faac2");
    # my $private_key = pack("H*", "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");
    $private_key = clamp_x25519_private_key($private_key);
    my $server_public_key = $epoll::clients{fileno($client_socket)}{tls}{key_exchange};
    # ! test
    # my $server_public_key = pack("H*", "9d3c940d89690b84d08a60993c144eca684d1081287c834d5311bcf32bb9da1a");
    # my $server_public_key = pack("H*", "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f");
    my $private_key_int = bytes_to_int_little_endian($private_key);
    my $server_public_key_int = bytes_to_int_little_endian($server_public_key);
    print("PRIVATE KEY: " . unpack("H*", $private_key) . "\n");
    print("SERVER PUBLIC KEY: " . unpack("H*", $server_public_key) . "\n");
    my $shared_secret_int = x25519_multiplication($private_key_int, $server_public_key_int);
    my $shared_secret = int_to_bytes_little_endian($shared_secret_int);

    $epoll::clients{fileno($client_socket)}{tls}{shared_secret} = $shared_secret;
    print("SHAREDDDD SECRET: " . unpack("H*", $shared_secret) . "\n");
    
    return $shared_secret;
}

sub calculate_handshake_encryption_key {
    my ($shared_secret) = @_;

    # KDF-Expand-Label(Secret, Label, Context, Length) =
    #     HKDF-Expand(Secret, HkdfLabel, Length)

    # Where HkdfLabel is specified as:

    # struct {
    #     uint16 length = Length;
    #     opaque label<7..255> = "tls13 " + Label;
    #     opaque context<0..255> = Context;
    # } HkdfLabel;

    # Derive-Secret(Secret, Label, Messages) =
    #     HKDF-Expand-Label(Secret, Label,
    #                         Transcript-Hash(Messages), Hash.length)
    my $client_hello = $epoll::clients{fileno($main::client_socket)}{tls}{client_hello};
    my $server_hello = $epoll::clients{fileno($main::client_socket)}{tls}{server_hello};
    print("CLIENT HELLO: " . unpack("H*", $client_hello) . "\n");
    print("SERVER HELLO: " . unpack("H*", $server_hello) . "\n");
    my $transcript = $client_hello . $server_hello;
    $epoll::clients{fileno($main::client_socket)}{tls}{transcript} = $transcript;

#    If a given secret is not available, then the 0-value consisting of a
#    string of Hash.length bytes set to zeros is used.  Note that this
#    does not mean skipping rounds, so if PSK is not in use, Early Secret
#    will still be HKDF-Extract(0, 0).
    my $hash_length = 32;
    my $zero_psk = "\0" x $hash_length;
    my $zero = "\0" x $hash_length;
    my $early_secret = hkdf_extract($zero, $zero_psk);
    print("EARLY SECRET: " . unpack("H*", $early_secret) . "\n");

        # Derive-Secret(., "derived", "")
    my $derived_secret = derive_secret($early_secret, "derived", "");
    print("DERIVED SECRET: " . unpack("H*", $derived_secret) . "\n");
    # |
    # v
#     (EC)DHE -> HKDF-Extract = Handshake Secret
    my $handshake_secret = hkdf_extract($derived_secret, $shared_secret);
    print("HANDSHAKE SECRET: " . unpack("H*", $handshake_secret) . "\n");
    # Derive-Secret(., "c hs traffic",
    #          |                     ClientHello...ServerHello)
    #          |                     = client_handshake_traffic_secret
    my $client_hs_traffic_secret = derive_secret($handshake_secret, "c hs traffic", $transcript);
    print("CLIENT HS TRAFFIC SECRET: " . unpack("H*", $client_hs_traffic_secret) . "\n");
    # Derive-Secret(., "s hs traffic",
    #          |                     ClientHello...ServerHello)
    #          |                     = server_handshake_traffic_secret
    my $server_hs_traffic_secret = derive_secret($handshake_secret, "s hs traffic", $transcript);
    print("SERVER HS TRAFFIC SECRET: " . unpack("H*", $server_hs_traffic_secret) . "\n");
    
    $derived_secret = derive_secret($handshake_secret, "derived", "");
    print("DERIVED SECRET: " . unpack("H*", $derived_secret) . "\n");
    
    my $master_secret = hkdf_extract($derived_secret, $zero);
    print("MASTER SECRET: " . unpack("H*", $master_secret) . "\n");

    my ($key_length, $iv_length) = get_key_and_iv_length_based_on_cipher_suite($epoll::clients{fileno($main::client_socket)}{tls}{cipher_suite});
    print("KEY LENGTH: $key_length\n");
    print("IV LENGTH: $iv_length\n");


    # [sender]_write_key = HKDF-Expand-Label(Secret, "key", "", key_length)
    # [sender]_write_iv  = HKDF-Expand-Label(Secret, "iv", "", iv_length)
    my $server_key_handshake_traffic = hkdf_expand_label($server_hs_traffic_secret, "key", "", $key_length, 1);
    print("SERVER KEY: " . unpack("H*", $server_key_handshake_traffic) . "\n");
    my $server_iv_handshake_traffic  = hkdf_expand_label($server_hs_traffic_secret, "iv",  "", $iv_length, 1);
    print("SERVER IV: " . unpack("H*", $server_iv_handshake_traffic) . "\n");
    
    my $client_key_handshake_traffic = hkdf_expand_label($client_hs_traffic_secret, "key", "", $key_length, 1);
    print("CLIENT KEY: " . unpack("H*", $client_key_handshake_traffic) . "\n");
    my $client_iv_handshake_traffic  = hkdf_expand_label($client_hs_traffic_secret, "iv",  "", $iv_length, 1);
    print("CLIENT IV: " . unpack("H*", $client_iv_handshake_traffic) . "\n");

    my %encryption_key = (
        "client_key" => $client_key_handshake_traffic,
        "client_iv" => $client_iv_handshake_traffic,
        "server_key" => $server_key_handshake_traffic,
        "server_iv" => $server_iv_handshake_traffic,
    );

    $epoll::clients{fileno($main::client_socket)}{tls}{handshake_encryption_key} = \%encryption_key;
    $epoll::clients{fileno($main::client_socket)}{tls}{server_hs_traffic_secret} = $server_hs_traffic_secret;
    $epoll::clients{fileno($main::client_socket)}{tls}{master_secret} = $master_secret;
    return \%encryption_key;
}

sub calculate_appliation_traffic_encryption_key {

    $epoll::clients{fileno($main::client_socket)}{tls}{record_sequence_number} = 0;

    my $transcript = $epoll::clients{fileno($main::client_socket)}{tls}{transcript};
    foreach my $key (sort { $a <=> $b } keys %{$epoll::clients{fileno($main::client_socket)}{tls}{application_data}}) {
        print("KEY: $key\n");
        $transcript .= decrypt_server_parameter($key);
    }

    my $finished_message = create_finished_message(hkdf_expand_label($epoll::clients{fileno($main::client_socket)}{tls}{server_hs_traffic_secret}, "finished", "", 32, 1));
    print("SOCKET: $main::client_socket\n");
    send($main::client_socket, $finished_message, 0) or die "send: $!";
    # print("FINISHED MESSAGE: " . unpack("H*", $finished_message) . "\n");
    $transcript = $transcript . $finished_message;
    # print("TRANSCRIPT: " . unpack("H*", $transcript) . "\n");
    my $hash = hash_based_on_cipher_suite($transcript);
    print("HASH: " . unpack("H*", $hash) . "\n");
    my $client_application_traffic_secret_0 = derive_secret($epoll::clients{fileno($main::client_socket)}{tls}{master_secret}, "c ap traffic", $transcript);
    print("CLIENT APPLICATION TRAFFIC SECRET 0: " . unpack("H*", $client_application_traffic_secret_0) . "\n");

    my $server_application_traffic_secret_0 = derive_secret($epoll::clients{fileno($main::client_socket)}{tls}{master_secret}, "s ap traffic", $transcript);
    print("SERVER APPLICATION TRAFFIC SECRET 0: " . unpack("H*", $server_application_traffic_secret_0) . "\n");

    my $exporter_master_secret = derive_secret($epoll::clients{fileno($main::client_socket)}{tls}{master_secret}, "exp master", $transcript);
    print("EXPORTER MASTER SECRET: " . unpack("H*", $exporter_master_secret) . "\n");

    my $resumption_master_secret = derive_secret($epoll::clients{fileno($main::client_socket)}{tls}{master_secret}, "res master", $transcript);
    print("RESUMPTION MASTER SECRET: " . unpack("H*", $resumption_master_secret) . "\n");

    # For the client (for outgoing messages)
    my $client_write_key = hkdf_expand_label($client_application_traffic_secret_0, "key", "", 16, 1);
    my $client_write_iv  = hkdf_expand_label($client_application_traffic_secret_0, "iv",  "", 12, 1);

    # For the server (for incoming messages)
    my $server_write_key = hkdf_expand_label($server_application_traffic_secret_0, "key", "", 16, 1);
    my $server_write_iv  = hkdf_expand_label($server_application_traffic_secret_0, "iv",  "", 12, 1);

    my $application_write_key = {
        "client_key" => $client_write_key,
        "client_iv" => $client_write_iv,
        "server_key" => $server_write_key,
        "server_iv" => $server_write_iv,
    };

    $epoll::clients{fileno($main::client_socket)}{tls}{application_write_key} = $application_write_key;
    $epoll::clients{fileno($main::client_socket)}{tls}{client_record_counter} = 0;
    $epoll::clients{fileno($main::client_socket)}{tls}{server_record_counter} = 0;
    return $application_write_key;
}
sub create_finished_message {
    my ($finished) = @_;

    my $finished_message = add_to_handshake_structure($finished, $handshake_structure{finished});

    return $finished_message;
}

sub hkdf_extract { #https://datatracker.ietf.org/doc/html/rfc5869
    my ($salt, $secret) = @_;
    
    my $prk = hmac_sha256($secret, $salt);
    
    return $prk;
}

sub derive_secret {
    my ($secret, $label, $transcript) = @_;
    # Derive-Secret(Secret, Label, Messages) =
    #         HKDF-Expand-Label(Secret, Label,
    #                           Transcript-Hash(Messages), Hash.length)
    print("SECRET: " . unpack("H*", $secret) . "\n");
    my $transcript_hash = hash_based_on_cipher_suite($transcript);
    print("HASH: " . unpack("H*", $transcript_hash) . "\n");
    my $transcript_length = length($transcript_hash);
    print("TRANSCRIPT LENGTH: $transcript_length\n");
    my $derived_secret = hkdf_expand_label($secret, $label, $transcript_hash, $transcript_length);

    return $derived_secret;
}

sub hkdf_expand_label {
    #  struct {
    #        uint16 length = Length;
    #        opaque label<7..255> = "tls13 " + Label;
    #        opaque context<0..255> = Context;
    #    } HkdfLabel;

    # HKDF-Expand-Label(Secret, Label, Context, Length) =
    #         HKDF-Expand(Secret, HkdfLabel, Length)

    my ($secret, $label, $context, $length, $zero_seperator) = @_;
    print("CONTEXT: " . unpack("H*", $context) . "\n");
    $label = "tls13 " . $label;
    my $seperator;
    if ($zero_seperator) {
        $seperator = pack("C", "");
    } else {
        $seperator = pack("C", ord(" "));
    }
    print("LENGTH: " . unpack("H*", pack("n", $length)) . "\n");
    print("LABEL: " . unpack("H*", $label) . "\n");
    print("SEPERATOR: " . unpack("H*", $seperator) . "\n");
    print("CONTEXT: " . unpack("H*", $context) . "\n");
    my $hkdf_label = pack("n", $length) . pack("C", length($label)) . $label . $seperator . $context;
    print("HKDF LABEL: " . unpack("H*", $hkdf_label) . "\n");
    print("LENGTH: $length\n");
    my $hkdf_expand_label = hkdf_expand($secret, $hkdf_label, $length);
}


sub hkdf_expand {
    my ($secret, $info, $length) = @_;
    print("SECRET: " . unpack("H*", $secret) . "\n");
    print("INFO: " . unpack("H*", $info) . "\n");
    print("LENGTH: $length\n");
    # For SHA-256, the hash output length is 32 bytes.
    my $hash_len = 32;

    # Calculate the number of rounds (N) needed.
    # N = ceil(length / hash_len)
    my $N = int(($length + $hash_len - 1) / $hash_len);

    my $T = "";
    my $okm = "";

    # Iterate for each round i from 1 to N.
    for (my $i = 1; $i <= $N; $i++) {
        # Compute T(i) = HMAC_SHA256(T(i-1) || info || i, secret)
        $T = hmac_sha256($T . $info . chr($i), $secret);
        $okm .= $T;
    }

    print("OKM: " . unpack("H*", $okm) . "\n");

    # Return the first $length bytes of the concatenated output.
    return substr($okm, 0, $length);
}


my %cipher_to_key_iv_length = (
    0x1301 => [16, 12],
);

sub get_key_and_iv_length_based_on_cipher_suite {
    my ($cipher_suite) = @_;

    return @{$cipher_to_key_iv_length{unpack("n", $cipher_suite)}};
}

my %cipher_to_hash = (
    0x1301 => "sha256",
);

my %create_hash = (
    sha256 => \&create_sha256,
);

sub hash_based_on_cipher_suite {
    my ($data) = @_;

    my $cipher_suite = $epoll::clients{fileno($main::client_socket)}{tls}{cipher_suite};
    my $hash_algorithm = get_hash_algorithm_based_on_cipher_suite($cipher_suite);
    return $create_hash{$hash_algorithm}($data) or die "Cannot create hash";
}

sub create_sha256 {
    my ($data) = @_;

    my $sha256 = Digest::SHA->new(256);
    $sha256->add($data);
    my $digest = $sha256->digest;
    return $digest;
}

sub get_hash_algorithm_based_on_cipher_suite {
    my ($cipher_suite) = @_;
    
    # print("CIHPER SUITE: $cipher_suite\n");
    # print("CIPHER SUITE: " . unpack("H*", $cipher_suite) . "\n");

    return $cipher_to_hash{unpack("n", $cipher_suite)};
}

sub create_sha384 {
    my ($data) = @_;

    my $sha384 = Digest::SHA->new(384);
    $sha384->add($data);
    my $digest = $sha384->digest;
    return $digest;
}


sub decrypt_server_parameter {
    my ($key) = @_;
    # struct {
    #       Extension extensions<0..2^16-1>;
    #   } EncryptedExtensions;

    #   K_LEN is 16 octets,

    #   P_MAX is 2^36 - 31 octets,

    #   A_MAX is 2^61 - 1 octets,

    #   N_MIN and N_MAX are both 12 octets, and

    #   C_MAX is 2^36 - 15 octets.

    #   struct {
    #       opaque content[TLSPlaintext.length];
    #       ContentType type;
    #       uint8 zeros[length_of_padding];
    #   } TLSInnerPlaintext;

    #   struct {
    #       ContentType opaque_type = application_data; /* 23 */
    #       ProtocolVersion legacy_record_version = 0x0303; /* TLS v1.2 */
    #       uint16 length;
    #       opaque encrypted_record[TLSCiphertext.length];
    #   } TLSCiphertext;
    my $client_fd = fileno($main::client_socket);
    
    
    
    

  
#    1.  The 64-bit record sequence number is encoded in network byte
#        order and padded to the left with zeros to iv_length.

#    2.  The padded sequence number is XORed with either the static
#        client_write_iv or server_write_iv (depending on the role).

#    The resulting quantity (of length iv_length) is used as the
#    per-record nonce.
    
    
    
    my $handshake_encryption_keys = $epoll::clients{fileno($main::client_socket)}{tls}{handshake_encryption_key};

    my $encrypted_data = $epoll::clients{$client_fd}{tls}{application_data}{$key};
    print("Encrypted data: " . unpack("H*", $encrypted_data) . "\n");

    my $server_write_key = $handshake_encryption_keys->{server_key};
    my $iv = $handshake_encryption_keys->{server_iv};
    my $record_sequence_number = $epoll::clients{$client_fd}{tls}{record_sequence_number};
    my $decrypted_data = decrypt_data($encrypted_data, $server_write_key, $iv, $record_sequence_number);
    

    # additional_data = TLSCiphertext.opaque_type ||
    #                 TLSCiphertext.legacy_record_version ||
    #                 TLSCiphertext.length
    

    # K_LEN is 16 octets, only AES-GCM for now
    
    
    

    
    
    
    
    
    
    
    $epoll::clients{$client_fd}{tls}{decrypted_application_data}{$key} = $decrypted_data;
    my $full_size = length($encrypted_data);
    print("FULL SIZE: $full_size\n");
    my $offset = 0;
    print("ENCRYPTED data: " . unpack("H*", $encrypted_data) . "\n");
    return $decrypted_data;
}

sub decrypt_data {
    my ($encrypted_data, $key, $iv, $record_sequence_number) = @_;

    if (!$record_sequence_number) {
        $record_sequence_number = 0;
    }
    my $static_server_write_iv = $iv;
    my $server_write_key = $key;
    my $nonce = compute_nonce($record_sequence_number, $static_server_write_iv);
    print("NONCE: " . unpack("H*", $nonce) . "\n");

    my $additional_data = pack("C", 23) . pack("n", 0x0303) . pack("n", length($encrypted_data));
    print("ADDITIONAL DATA: " . unpack("H*", $additional_data) . "\n");
    my $tag_length = 16;  
    my $ciphertext = substr($encrypted_data, 0, -$tag_length);
    my $tag = substr($encrypted_data, -$tag_length);
    my $decrypted_data = AEAD_decrypt($server_write_key, $nonce, $additional_data, $ciphertext, $tag);
    print("DECRYPTED DATA" . unpack("H*", $decrypted_data) . "\n");
    if (!defined $decrypted_data) {
        die "Decryption failed: bad_record_mac or incorrect parameters.";
    }
    $decrypted_data = substr($decrypted_data, 0, -1);
    print("DECRYPTED data: " . unpack("H*", $decrypted_data) . "\n");
    $epoll::clients{fileno($main::client_socket)}{tls}{record_sequence_number}++;
}

sub AEAD_decrypt {
    #   plaintext of encrypted_record =
    #       AEAD-Decrypt(peer_write_key, nonce,
    #                    additional_data, AEADEncrypted)
    my ($write_key, $nonce, $additional_data, $encrypted_data, $tag) = @_;

    my $cipher = Crypt::GCM->new(-key => $write_key, -cipher => 'Crypt::Cipher::AES');
    $cipher->set_iv($nonce);
    $cipher->aad($additional_data);
    $cipher->tag($tag);
    print("CIHPER: $cipher\n");
    print("ENCRYPTED DATA: " . unpack("H*", $encrypted_data) . "\n");
    my $decrypted_data = $cipher->decrypt($encrypted_data) or die "Cannot decrypt data $!";
    print("DECRYPTED DATA: " . unpack("H*", $decrypted_data) . "\n");
    return $decrypted_data;
}

sub AEAD_encrypt {
    my ($write_key, $nonce, $additional_data, $data, $tag_length) = @_;

    my $cipher = Crypt::GCM->new(-key => $write_key, -cipher => 'Crypt::Cipher::AES');
    $cipher->set_iv($nonce);
    $cipher->aad($additional_data);
    my $ciphertext = $cipher->encrypt($data) or die "Cannot encrypt data $!";
    my $tag = $cipher->tag;
    return ($ciphertext, $tag);
}

sub compute_nonce {
    my ($record_sequence_number, $static_iv) = @_;

    my $iv_length = length($static_iv);
    print("IV LENGTH: $iv_length\n");
    my $padded_sequence_number = pack("Q>", $record_sequence_number);
    print("PADDED SEQUENCE NUMBER: " . unpack("H*", $padded_sequence_number) . "\n");
    $padded_sequence_number = "\0" x ($iv_length - length($padded_sequence_number)) . $padded_sequence_number;
    print("PADDED SEQUENCE NUMBER: " . unpack("H*", $padded_sequence_number) . "\n");
    my $nonce = $padded_sequence_number ^ $static_iv;
    print("NONCE: " . unpack("H*", $nonce) . "\n");

    return $nonce;
}


sub parse_tls_record {
    my ($data, $client_socket, $offset) = @_;

    my $content_type = unpack("C", substr($data, $offset, 1));
    print("OFFSET1: $offset\n");
    print("CONTENT TYPE: $content_type\n");
    print("CONTENT TYPE: " . unpack("H*", substr($data, $offset, 1)) . "\n");
    if (!$content_type) {
        my $last_content_type = $epoll::clients{fileno($client_socket)}{tls}{last_content_type};
        if ($last_content_type) {
            $epoll::clients{fileno($client_socket)}{tls}{is_continuation} = 1;
            $content_type = $last_content_type;
        } else {
            return $offset;
        }
    } else {
        $epoll::clients{fileno($client_socket)}{tls}{is_continuation} = 0;
    }
    # enum {
    #       invalid(0),
    #       change_cipher_spec(20),
    #       alert(21),
    #       handshake(22),
    #       application_data(23),
    #       (255)
    #   } ContentType;

    # struct {
    #       ContentType type;
    #       ProtocolVersion legacy_record_version;
    #       uint16 length;
    #       opaque fragment[TLSPlaintext.length];
    #   } TLSPlaintext;

    if ($content_type == 22) {
        $offset = get_server_random($data, $offset);
    } elsif ($content_type == 21) {
        $offset = parse_alert($data, $offset);
    } elsif ($content_type == 20) {
        $offset = parse_change_cipher_spec($data, $offset);
    } elsif ($content_type == 23) {
        $offset = parse_application_data($data, $offset);
    }

    

    return $offset;
}

sub establish_tls_connection {
    my ($host, $port) = @_;
    print("HOST: $host\n");
    print("PORT: $port\n");
    my $ip = gethostbyname($host);
    $ip = inet_ntoa($ip);
    print("IP: $ip\n");
    socket(my $socket, PF_INET, SOCK_STREAM, getprotobyname('tcp')) or die "socket: $!";
    connect($socket, sockaddr_in($port, inet_aton($host))) or die "connect: $!";

    perform_tls_handshake($socket, $host);

    return $socket;
}

sub perform_tls_handshake {
    my ($socket, $host) = @_;

    my $client_random = generate_client_random() or die "Cannot generate client random";
    my $client_hello = create_client_hello($client_random, $host) or die "Cannot create client hello";
    send($socket, $client_hello, 0) or die "send: $!";

    recv($socket, my $response, 4096, 0);
    my $server_hello = $response;
    my $server_hello_test_file = "server_hello";
    open my $fh, ">", $server_hello_test_file or die "Cannot open $server_hello_test_file: $!";
    print $fh $server_hello;
    close $fh;

    my $server_random = get_server_random($server_hello);
    my $server_certificate = get_server_certificate($server_hello);

    verify_certificate($server_certificate, $host);

    my $pre_master_secret = generate_pre_master_secret();
    my $encrypted_pre_master_secret = encrypt_pre_master_secret($pre_master_secret, $server_certificate);
    send($socket, $encrypted_pre_master_secret, 0) or die "send $!";

    my $master_secret = generate_master_secret($pre_master_secret, $server_random, $client_random);
    my %session_keys = generate_session_keys($master_secret, $server_random, $client_random);

    send_change_cipher_spec($socket);
    send_finished_message($socket, \%session_keys);
}

sub initiate_handshake {
    # struct {
    #       HandshakeType msg_type;    /* handshake type */
    #       uint24 length;             /* remaining bytes in message */
    #       select (Handshake.msg_type) {
    #           case client_hello:          ClientHello;
    #           case server_hello:          ServerHello;
    #           case end_of_early_data:     EndOfEarlyData;
    #           case encrypted_extensions:  EncryptedExtensions;
    #           case certificate_request:   CertificateRequest;
    #           case certificate:           Certificate;
    #           case certificate_verify:    CertificateVerify;
    #           case finished:              Finished;
    #           case new_session_ticket:    NewSessionTicket;
    #           case key_update:            KeyUpdate;
    #       };
    #   } Handshake;


}


sub generate_client_random {
    open my $fh, '<', '/dev/urandom' or die "Cannot open /dev/urandom: $!";
    read $fh, my $client_random, 32 or die "Cannot read from /dev/urandom: $!";
    close $fh;
    return $client_random;
}


my %supported_cipher_suites = (
    # "TLS_AES_128_CCM_8_SHA256" => 0x1305,
    # "TLS_AES_128_CCM_SHA256" => 0x1304,
    # "TLS_ECCPWD_WITH_AES_128_CCM_SHA256" => 0xC0B2,
    # "TLS_ECCPWD_WITH_AES_256_CCM_SHA384" => 0xC0B3,
    # "TLS_ECDHE_ECDSA_WITH_AES_128_CCM" => 0xC0AC,
    "TLS_AES_128_GCM_SHA256" => 0x1301,

);

sub create_client_hello { #https://datatracker.ietf.org/doc/html/rfc8446#section-4.1.2
    my ($client_random, $host) = @_;
    
    # uint16 ProtocolVersion;
    #   opaque Random[32];

    #   uint8 CipherSuite[2];    /* Cryptographic suite selector */

    #   struct {
    #       ProtocolVersion legacy_version = 0x0303;    /* TLS v1.2 */
    #       Random random;
    #       opaque legacy_session_id<0..32>;
    #       CipherSuite cipher_suites<2..2^16-2>;
    #       opaque legacy_compression_methods<1..2^8-1>;
    #       Extension extensions<8..2^16-1>;
    #   } ClientHello;


    # n = 16-bit unsigned big-endian integer
    # C = 8-bit unsigned number
    
    if (!$client_random || length($client_random) != 32) {
        return 0;
    }

    my $legacy_version = pack("n", 0x0303);

    my $random = $client_random;

    my $session_id = "";

    my $legacy_session_id = pack("C", length($session_id)) . $session_id;

    my $cipher_suites;
    foreach my $cipher_suite (keys %supported_cipher_suites) {
        $cipher_suites .= pack("n", $supported_cipher_suites{$cipher_suite});
    }
    my $cipher_suites_length = pack("n", length($cipher_suites));
    $cipher_suites = $cipher_suites_length . $cipher_suites;

    my $compression_methods = pack("C", 0);
    $compression_methods = pack("C", length($compression_methods)) . $compression_methods;

    my $extensions = get_client_hello_extensions($host);

    my $client_hello = $legacy_version 
                    . $random 
                    . $legacy_session_id 
                    . $cipher_suites 
                    . $compression_methods 
                    . $extensions;


    my $test_client_hello_file = "test_client_hello";

    $client_hello = add_to_handshake_structure($client_hello, $handshake_structure{client_hello});
    $epoll::clients{fileno($main::client_socket)}{tls}{client_hello} = $client_hello;
    $client_hello = encapsulate_in_tls_record($client_hello, $record_layer_structure{handshake});
    open(my $fh, ">", $test_client_hello_file) or die "Cannot open $test_client_hello_file: $!";
    print $fh $client_hello;
    close $fh;
    return $client_hello;
}

sub add_to_handshake_structure {
    my ($data, $msg_type) = @_;
    # struct {
    #       HandshakeType msg_type;    /* handshake type */
    #       uint24 length;             /* remaining bytes in message */
    #       select (Handshake.msg_type) {
    #           case client_hello:          ClientHello;
    #           case server_hello:          ServerHello;
    #           case end_of_early_data:     EndOfEarlyData;
    #           case encrypted_extensions:  EncryptedExtensions;
    #           case certificate_request:   CertificateRequest;
    #           case certificate:           Certificate;
    #           case certificate_verify:    CertificateVerify;
    #           case finished:              Finished;
    #           case new_session_ticket:    NewSessionTicket;
    #           case key_update:            KeyUpdate;
    #       };
    #   } Handshake;

    $msg_type = pack("C", $msg_type);
    my $length = length($data);

    my $uint24_length = pack("C3", ($length >> 16) & 0xFF, ($length >> 8) & 0xFF, $length & 0xFF);
    $data = $msg_type . $uint24_length . $data;
    return $data;
}

sub encapsulate_in_tls_record {
    my ($data, $content_type) = @_;
    #  enum {
    #       invalid(0),
    #       change_cipher_spec(20),
    #       alert(21),
    #       handshake(22),
    #       application_data(23),
    #       (255)
    #   } ContentType;

    #   struct {
    #       ContentType type;
    #       ProtocolVersion legacy_record_version;
    #       uint16 length;
    #       opaque fragment[TLSPlaintext.length];
    #   } TLSPlaintext;
    $content_type = pack("C", $content_type);
    my $legacy_record_version = pack("n", 0x0301);
    my $length = pack("n", length($data));
    $data = $content_type . $legacy_record_version . $length . $data;
    return $data;
}

my %extensions = (
    "supported_versions" => \&get_supported_versions_extension,
    "signature_algorithms" => \&get_signature_algorithms_extension,
    "supported_groups" => \&get_supported_groups_extension,
    "server_name" => \&get_server_name_extension,
    "key_share" => \&get_key_share_extension,
);

my %extension_types = (
    # enum {
    #     server_name(0),                             /* RFC 6066 */
    #     max_fragment_length(1),                     /* RFC 6066 */
    #     status_request(5),                          /* RFC 6066 */
    #     supported_groups(10),                       /* RFC 8422, 7919 */
    #     signature_algorithms(13),                   /* RFC 8446 */
    #     use_srtp(14),                               /* RFC 5764 */
    #     heartbeat(15),                              /* RFC 6520 */
    #     application_layer_protocol_negotiation(16), /* RFC 7301 */
    #     signed_certificate_timestamp(18),           /* RFC 6962 */
    #     client_certificate_type(19),                /* RFC 7250 */
    #     server_certificate_type(20),                /* RFC 7250 */
    #     padding(21),                                /* RFC 7685 */
    #     pre_shared_key(41),                         /* RFC 8446 */
    #     early_data(42),                             /* RFC 8446 */
    #     supported_versions(43),                     /* RFC 8446 */
    #     cookie(44),                                 /* RFC 8446 */
    #     psk_key_exchange_modes(45),                 /* RFC 8446 */
    #     certificate_authorities(47),                /* RFC 8446 */
    #     oid_filters(48),                            /* RFC 8446 */
    #     post_handshake_auth(49),                    /* RFC 8446 */
    #     signature_algorithms_cert(50),              /* RFC 8446 */
    #     key_share(51),                              /* RFC 8446 */
    #     (65535)
    # } ExtensionType;
    "server_name" => 0,
    "supported_groups" => 10,
    "signature_algorithms" => 13,
    "supported_versions" => 43,
    "key_share" => 51,
);

sub get_client_hello_extensions {
    my ($host) = @_;
    # struct {
    #     ExtensionType extension_type;
    #     opaque extension_data<0..2^16-1>;
    # } Extension;

    my $extensions;
    foreach my $extension (keys %extensions) {
        my $extension_data = $extensions{$extension}->($host);
        my $extension_type = pack("n", $extension_types{$extension});
        my $extension_length = pack("n", length($extension_data));
        $extensions .= $extension_type . $extension_length . $extension_data;
    }

    $extensions = pack("n", length($extensions)) . $extensions;

    return $extensions;
}

my %supported_tls_versions = (
    "TLSv1.3" => 0x0304,
);

sub get_supported_versions_extension {
    # struct {
    #     ProtocolVersion versions<2..254>;
    # } SupportedVersions;

    my $supported_versions;
    foreach my $version (sort { $supported_tls_versions{$b} <=> $supported_tls_versions{$a} } keys %supported_tls_versions) {
        $supported_versions .= pack("n", $supported_tls_versions{$version});
    }
    $supported_versions = pack("C", length($supported_versions)) . $supported_versions;

    return $supported_versions;
}

my %supported_signature_algorithms = (
    #   enum {
    #       /* RSASSA-PKCS1-v1_5 algorithms */
    #       rsa_pkcs1_sha256(0x0401),
    #       rsa_pkcs1_sha384(0x0501),
    #       rsa_pkcs1_sha512(0x0601),

    #       /* ECDSA algorithms */
    #       ecdsa_secp256r1_sha256(0x0403),
    #       ecdsa_secp384r1_sha384(0x0503),
    #       ecdsa_secp521r1_sha512(0x0603),

    #       /* RSASSA-PSS algorithms with public key OID rsaEncryption */
    #       rsa_pss_rsae_sha256(0x0804),
    #       rsa_pss_rsae_sha384(0x0805),
    #       rsa_pss_rsae_sha512(0x0806),

    #       /* EdDSA algorithms */
    #       ed25519(0x0807),
    #       ed448(0x0808),

    #       /* RSASSA-PSS algorithms with public key OID RSASSA-PSS */
    #       rsa_pss_pss_sha256(0x0809),
    #       rsa_pss_pss_sha384(0x080a),
    #       rsa_pss_pss_sha512(0x080b),

    #       /* Legacy algorithms */
    #       rsa_pkcs1_sha1(0x0201),
    #       ecdsa_sha1(0x0203),

    #       /* Reserved Code Points */
    #       private_use(0xFE00..0xFFFF),
    #       (0xFFFF)
    #   } SignatureScheme;
    "rsa_pkcs1_sha256" => 0x0401,
    "rsa_pkcs1_sha384" => 0x0501,
    "rsa_pkcs1_sha512" => 0x0601,

    "ecdsa_secp256r1_sha256" => 0x0403,
    "ecdsa_secp384r1_sha384" => 0x0503,
    "ecdsa_secp521r1_sha512" => 0x0603,

    "rsa_pss_rsae_sha256" => 0x0804,
    "rsa_pss_rsae_sha384" => 0x0805,
    "rsa_pss_rsae_sha512" => 0x0806,

    "ed25519" => 0x0807,
    "ed448" => 0x0808,

    "rsa_pss_pss_sha256" => 0x0809,
    "rsa_pss_pss_sha384" => 0x080a,
    "rsa_pss_pss_sha512" => 0x080b,
);

sub get_signature_algorithms_extension {
    # struct {
    #       SignatureScheme supported_signature_algorithms<2..2^16-2>;
    #   } SignatureSchemeList;

    my $supported_signature_algorithms;
    foreach my $signature_algorithm (keys %supported_signature_algorithms) {
        $supported_signature_algorithms .= pack("n", $supported_signature_algorithms{$signature_algorithm});
    }
    $supported_signature_algorithms = pack("n", length($supported_signature_algorithms)) . $supported_signature_algorithms;

    return $supported_signature_algorithms;
}

my %supported_groups = (
#    enum {

#           /* Elliptic Curve Groups (ECDHE) */
#           secp256r1(0x0017), secp384r1(0x0018), secp521r1(0x0019),
#           x25519(0x001D), x448(0x001E),

#           /* Finite Field Groups (DHE) */
#           ffdhe2048(0x0100), ffdhe3072(0x0101), ffdhe4096(0x0102),
#           ffdhe6144(0x0103), ffdhe8192(0x0104),

#           /* Reserved Code Points */
#           ffdhe_private_use(0x01FC..0x01FF),
#           ecdhe_private_use(0xFE00..0xFEFF),
#           (0xFFFF)
#       } NamedGroup;

    # "secp256r1" => 0x0017,
    # "secp384r1" => 0x0018,
    # "secp521r1" => 0x0019,
    "x25519" => 0x001D,
    # "x448" => 0x001E,

    # "ffdhe2048" => 0x0100,
    # "ffdhe3072" => 0x0101,
    # "ffdhe4096" => 0x0102,
    # "ffdhe6144" => 0x0103,
    # "ffdhe8192" => 0x0104,
);

sub get_supported_groups_extension {
    # struct {
    #     NamedGroup supported_groups<2..2^16-1>;
    # } NamedGroupList;


    my $supported_groups;
    foreach my $group (keys %supported_groups) {
        $supported_groups .= pack("n", $supported_groups{$group});
    }
    $supported_groups = pack("n", length($supported_groups)) . $supported_groups;

    return $supported_groups;
}

sub get_server_name_extension {
    my ($host) = @_;
    # struct {
    #       NameType name_type;
    #       select (name_type) {
    #           case host_name: HostName;
    #       } name;
    #   } ServerName;

    #   enum {
    #       host_name(0), (255)
    #   } NameType;

    #   opaque HostName<1..2^16-1>;

    #   struct {
    #       ServerName server_name_list<1..2^16-1>
    #   } ServerNameList;

    my $HostName;
    foreach my $char (split(//, $host)) {
        $HostName .= pack("C", ord($char));
    }
    my $human_Readable_host = $host;
    print("HostName: $HostName\n");

    my $ServerName = pack("C", 0) . pack("n", length($HostName)) . $HostName;
    print("ServerName: $ServerName\n");
    
    my $ServerNameList = pack("n", length($ServerName)) . $ServerName;

    return $ServerNameList;
}

my %supported_key_share_groups = (
    "x25519"    => 0x001D,
);
#! angucken wie geht, nix checken
sub get_key_share_extension {
    # struct {
    #       NamedGroup group;
    #       opaque key_exchange<1..2^16-1>;
    #   } KeyShareEntry;

    # group:  The named group for the key being exchanged.


    # struct {
    #       KeyShareEntry client_shares<0..2^16-1>;
    #   } KeyShareClientHello;

    # client_shares:  A list of offered KeyShareEntry values in descending
    # order of client preference.

    my ($private_key, $public_key) = generate_x25519_key_pair();
    $epoll::clients{fileno($main::client_socket)}{tls}{private_key} = $private_key;
    $epoll::clients{fileno($main::client_socket)}{tls}{public_key} = $public_key;

    my $key_exchange = pack("n", length($public_key)) . $public_key;

    my $KeyShareEntry = pack("n", $supported_key_share_groups{"x25519"}) . $key_exchange;

    my $client_shares = pack("n", length($KeyShareEntry)) . $KeyShareEntry;

    return $client_shares;
}

sub generate_x25519_key_pair { #https://datatracker.ietf.org/doc/html/rfc7748
    my $private_key = generate_x25519_private_key();
    my $public_key = calculate_x25519_public_key($private_key);

    return ($private_key, $public_key);
}

sub calculate_x25519_public_key {
    my ($private_key) = @_;

    my $scalar_int = bytes_to_int_little_endian($private_key);
    print("SCALAR: $scalar_int \n");
    my $u_coordinate_int = 9; #bytes_to_int_little_endian(pack("H*", "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"));
    print("U COORDINATE: $u_coordinate_int\n");
    my $public_key_int = x25519_multiplication($scalar_int, $u_coordinate_int);
    print("PUBLIC KEY INT: $public_key_int\n");
    my $public_key = int_to_bytes_little_endian($public_key_int);
    print("PUBLIC KEY: " . unpack("H*", $public_key) . "\n");
    
    return $public_key;
}

sub hex_to_int {
    my ($hex) = @_;
    return hex($hex);
}

sub int_to_bytes {
    my ($int) = @_;

    my $bytes = "";
    while ($int > 0) {
        $bytes = pack("C", $int & 0xFF) . $bytes;
        $int >>= 8;
    }

    return $bytes;
}

sub x25519_multiplication {
    my ($scalar, $u_coordinate) = @_;

#     All calculations are performed
#    in GF(p), i.e., they are performed modulo p.  The constant a24 is
#    (486662 - 2) / 4 = 121665 for curve25519/X25519 and (156326 - 2) / 4
#    = 39081 for curve448/X448.

    my $a24 = 121665;

#    p  2^255 - 19
    my $p = 2**255 - 19;
#    x_1 = u
#    x_2 = 1
#    z_2 = 0
#    x_3 = u
#    z_3 = 1
#    swap = 0
    print("START\n");
    use Time::HiRes qw(time);
    my $start_time = time();
    my $x_1 = $u_coordinate;
    my $x_2 = 1;
    my $z_2 = 0;
    my $x_3 = $u_coordinate;
    my $z_3 = 1;
    my $swap = 0;

#    For t = bits-1 down to 0:
    for (my $t = 254; $t >= 0; $t--) {#
        # print("T: $t\n");
#        k_t = (k >> t) & 1
        my $k_t = ($scalar >> $t) & 1; # ? shifts bits of $scalar to the right by $t and then ANDs the result with 1, example: 11001100 (204) >> 3 = 00011001 (25), 00011001 & 00000001 = 00000001 (1), 
        # print("K_T: $k_t\n");
#        swap ^= k_t
        $swap ^= $k_t; # ? XOR 1 and 1 = 0, XOR 0 and 1 = 1
        # print("SWAP: $swap\n");
#        // Conditional swap; see text below.
#        (x_2, x_3) = cswap(swap, x_2, x_3)
#        (z_2, z_3) = cswap(swap, z_2, z_3)
        ($x_2, $x_3) = x25519_cswap($swap, $x_2, $x_3);
        ($z_2, $z_3) = x25519_cswap($swap, $z_2, $z_3);
        # print("X_2: $x_2\n");
        # print("X_3: $x_3\n");
        # print("Z_2: $z_2\n");
        # print("Z_3: $z_3\n");
#        swap = k_t
        $swap = $k_t;
        # print("SWAP: $swap\n");


#        A = x_2 + z_2
        my $A = ($x_2 + $z_2) % $p;
        # print("A: $A\n");
#        AA = A^2
        my $AA = ($A * $A) % $p;
        # print("AA: $AA\n");
#        B = x_2 - z_2
        my $B = ($x_2 - $z_2) % $p;
        # print("B: $B\n");
#        BB = B^2
        my $BB = ($B * $B) % $p;
        # print("BB: $BB\n");
#        E = AA - BB
        my $E = ($AA - $BB) % $p;
        # print("E: $E\n");
#        C = x_3 + z_3
        my $C = ($x_3 + $z_3) % $p;
        # print("C: $C\n");
#        D = x_3 - z_3
        my $D = ($x_3 - $z_3) % $p;
        # print("D: $D\n");
#        DA = D * A
        my $DA = ($D * $A) % $p;
        # print("DA: $DA\n");
#        CB = C * B
        my $CB = ($C * $B) % $p;
        # print("CB: $CB\n");
#        x_3 = (DA + CB)^2
        $x_3 = (($DA + $CB) * ($DA + $CB)) % $p;
        # print("X_3: $x_3\n");
#        z_3 = x_1 * (DA - CB)^2
        $z_3 = ($x_1 * (($DA - $CB) * ($DA - $CB))) % $p;
        # print("Z_3: $z_3\n");
#        x_2 = AA * BB
        $x_2 = ($AA * $BB) % $p;
        # print("X_2: $x_2\n");
#        z_2 = E * (AA + a24 * E)
        $z_2 = ($E * ($AA + $a24 * $E)) % $p;
        # print("Z_2: $z_2\n");
    }
#    // Conditional swap; see text below.
#    (x_2, x_3) = cswap(swap, x_2, x_3)
#    (z_2, z_3) = cswap(swap, z_2, z_3)
    ($x_2, $x_3) = x25519_cswap($swap, $x_2, $x_3);
    ($z_2, $z_3) = x25519_cswap($swap, $z_2, $z_3);
    my $end_time = time();
    print("TIME: " . ($end_time - $start_time) . "\n");
    # print("X_2: $x_2\n");
    # print("X_3: $x_3\n");
    # print("Z_2: $z_2\n");
    # print("Z_3: $z_3\n");
    # print("P: $p\n");
    # print("CALCULATING: ($x_2 * ($z_2**($p - 2))) % $p\n");
#    Return x_2 * (z_2^(p - 2))
    # print("CALCULATING FINAL RESULT\n");
    my $z_inv = $z_2->copy->bmodpow($p-2, $p);
    my $result = $x_2->copy->bmul($z_inv)->bmod($p);
    print("RESULT: $result\n");

    return $result;


#    (Note that these formulas are slightly different from Montgomery's
#    original paper.  Implementations are free to use any correct
#    formulas.)

#    Finally, encode the resulting value as 32 or 56 bytes in little-
#    endian order.  For X25519, the unused, most significant bit MUST be
#    zero.

    

}

#    The cswap function SHOULD be implemented in constant time (i.e.,
#    independent of the swap argument).  For example, this can be done as
#    follows:
sub x25519_cswap {
#    cswap(swap, x_2, x_3):
    my ($swap, $x_2, $x_3) = @_;

#          dummy = mask(swap) AND (x_2 XOR x_3)
#    Where mask(swap) is the all-1 or all-0 word of the same length as x_2
#    and x_3, computed, e.g., as mask(swap) = 0 - swap.
    my $dummy = mask($swap) & ($x_2 ^ $x_3); # ? 1 or 0 AND x XOR y, example: 1 (00000001) AND 1 (00000001) XOR 0 (00000000) = 1, 0 (00000000) AND 1 (00000001) XOR 1 (00000001) = 0

#          x_2 = x_2 XOR dummy
    $x_2 ^= $dummy; # ? x_2 XOR 0 = x_2, x_2 XOR 1 = ~x_2
#          x_3 = x_3 XOR dummy
    $x_3 ^= $dummy; # ? x_3 XOR 0 = x_3, x_3 XOR 1 = ~x_3

#          Return (x_2, x_3)
    return ($x_2, $x_3);
}

sub mask {
    my ($swap) = @_;
    return 0 - $swap;   # ? When $swap is 1: 0 (00000000) - 1 (00000001) = -1 (11111111 in two's complement)
                        # ? When $swap is 0: 0 (00000000) - 0 (00000000) = 0 (00000000)
}

sub generate_x25519_private_key {
    # my $private_key = generate_client_random();
    my $private_key = pack("H*", "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");

    $private_key = clamp_x25519_private_key($private_key);

    return $private_key;
}

sub clamp_x25519_private_key {
    my ($key) = @_;

    # For X25519, in
    # order to decode 32 random bytes as an integer scalar, set the three
    # least significant bits of the first byte and the most significant bit
    # of the last to zero, set the second most significant bit of the last
    # byte to 1 and, finally, decode as little-endian.  This means that the
    # resulting integer is of the form 2^254 plus eight times a value
    # between 0 and 2^251 - 1 (inclusive).

    my @bytes = unpack("C*", $key);
    $bytes[0] &= 0xF8; # clear bits 0, 1, 2
    $bytes[31] &= 0x7F; # clear bit 7
    $bytes[31] |= 0x40; # set bit 6

    return pack("C*", @bytes);
}

sub bytes_to_int_little_endian {
    my ($bytes) = @_;

    my $int = 0;
    my $i = 0;
    foreach my $byte (unpack("C*", $bytes)) {
        $int += $byte << (8 * $i);
        # print("BYTE: $byte\n");
        # print("INT: $int\n");
        $i++;
    }

    return $int;
}

sub int_to_bytes_little_endian {
    my ($int) = @_;

    my $bytes;

    while ($int > 0) {
        $bytes .= pack("C", $int & 0xFF);
        $int >>= 8;
    }

    return $bytes;
}


sub get_server_random {
    my ($server_hello) = @_;

    # struct {
    #       ProtocolVersion legacy_version = 0x0303;    /* TLS v1.2 */
    #       Random random;
    #       opaque legacy_session_id_echo<0..32>;
    #       CipherSuite cipher_suite;
    #       uint8 legacy_compression_method = 0;
    #       Extension extensions<6..2^16-1>;
    #   } ServerHello;

    my $handshake_content_type = substr($server_hello, 0, 1);
    print("HANDSHAKE CONTENT TYPE: " . unpack("H*", $handshake_content_type) . "\n");
    print("HANDSHAKE CONTENT TYPE: " . unpack("C", $handshake_content_type) . "\n");
    if ($handshake_content_type ne "\x16") {
        return 0;
    }
    my $legacy_version = substr($server_hello, 1, 2);
    print("LEGACY VERSION: " . unpack("H*", $legacy_version) . "\n");
    if ($legacy_version ne "\x03\x03") {
        return 0;
    }
    my $handshake_struct_length = substr($server_hello, 3, 2);
    print("HANDSHAKE STRUCT LENGTH: " . unpack("H*", $handshake_struct_length) . "\n");
    my $handshake_struct_length_int = unpack("n", $handshake_struct_length);
    print("HANDSHAKE STRUCT LENGTH INT: $handshake_struct_length_int\n");
    my $server_hello_struct = substr($server_hello, 5, $handshake_struct_length_int);
    $epoll::clients{fileno($main::client_socket)}{tls}{server_hello} = $server_hello_struct;
    #! 
    # $epoll::clients{fileno($main::client_socket)}{tls}{server_hello} = pack ("H*", "020000560303eefce7f7b37ba1d1632e96677825ddf73988cfc79825df566dc5430b9a045a1200130100002e00330024001d00209d3c940d89690b84d08a60993c144eca684d1081287c834d5311bcf32bb9da1a002b00020304");
    
    my $handshake_struct = substr($server_hello, 5, $handshake_struct_length_int);
    my $message_type = substr($handshake_struct, 0, 1);
    print("MESSAGE TYPE: " . unpack("H*", $message_type) . "\n");
    my $server_hello_length = substr($handshake_struct, 1, 3); 
    my $server_hello_length_int = unpack("C", substr($server_hello_length, 0, 1)) << 16 |
                                  unpack("C", substr($server_hello_length, 1, 1)) << 8 |
                                  unpack("C", substr($server_hello_length, 2, 1));
    print("SERVER HELLO LENGTH: $server_hello_length_int\n");
    my $tls_version = substr($handshake_struct, 4, 2);
    print("TLS VERSION: " . unpack("H*", $tls_version) . "\n");
    my $server_secret = substr($handshake_struct, 6, 32);
    print("SERVER SECRET: " . unpack("H*", $server_secret) . "\n");
    if (length($server_secret) != 32) {
        return 0;
    }
    my $legacy_session_id_length = substr($handshake_struct, 38, 1);
    print("LEGACY SESSION ID LENGTH: " . unpack("H*", $legacy_session_id_length) . "\n");
    my $legacy_session_id = substr($handshake_struct, 39, unpack("C", $legacy_session_id_length));
    print("LEGACY SESSION ID: " . unpack("H*", $legacy_session_id) . "\n");
    my $cipher_suite = substr($handshake_struct, 39 + unpack("C", $legacy_session_id_length), 2);
    print("CIPHER SUITE: " . unpack("H*", $cipher_suite) . "\n");
    my $compression_method = substr($handshake_struct, 41 + unpack("C", $legacy_session_id_length), 1);
    print("COMPRESSION METHOD: " . unpack("H*", $compression_method) . "\n");
    my $extensions_length = substr($handshake_struct, 42 + unpack("C", $legacy_session_id_length), 2);
    my $extensions_length_int = unpack("n", $extensions_length);
    print("EXTENSIONS LENGTH: $extensions_length_int\n");
    my $extensions = substr($handshake_struct, 44 + unpack("C", $legacy_session_id_length), $extensions_length_int);
    print("EXTENSIONS: " . unpack("H*", $extensions) . "\n");
    my @extensions = get_server_extensions($extensions, $extensions_length_int);
    foreach my $extension (@extensions) {
        my $extension_type = $extension->{"type"};
        my $extension_length = $extension->{"length"};
        my $extension_data = $extension->{"data"};
        parse_extension_data($extension_type, $extension_length, $extension_data);
    }
    
    $epoll::clients{fileno($main::client_socket)}{tls}{tls_state}{2}{server_random} = $server_secret;
    $epoll::clients{fileno($main::client_socket)}{tls}{cipher_suite} = $cipher_suite;

    print("OFFSET123: $handshake_struct_length_int\n");
    return ($handshake_struct_length_int + 5)
}

sub get_server_extensions {
    my ($extensions, $extensions_length_int) = @_;

    my @extensions;
    my $extension_start = 0;
    while ($extension_start < $extensions_length_int) {
        my $extension_type = substr($extensions, $extension_start, 2);
        my $extension_type_int = unpack("n", $extension_type);
        print("EXTENSION TYPE: $extension_type_int\n");
        my $extension_length = substr($extensions, $extension_start + 2, 2);
        my $extension_length_int = unpack("n", $extension_length);
        print("EXTENSION LENGTH: $extension_length_int\n");
        my $extension_data = substr($extensions, $extension_start + 4, $extension_length_int);
        print("EXTENSION DATA: " . unpack("H*", $extension_data) . "\n");
        $extension_start += 4 + $extension_length_int;

        my %extension = (
            "type" => $extension_type_int,
            "length" => $extension_length_int,
            "data" => $extension_data,
        );

        push(@extensions, \%extension);
    }

    return @extensions;
}

sub parse_extension_data {
    my ($extension_type, $extension_length, $extension_data) = @_;

    if ($extension_type == $extension_types{"supported_versions"}) {
        parse_supported_versions_extension($extension_data);
    } elsif ($extension_type == $extension_types{"signature_algorithms"}) {
        parse_signature_algorithms_extension($extension_data);
    } elsif ($extension_type == $extension_types{"supported_groups"}) {
        parse_supported_groups_extension($extension_data);
    } elsif ($extension_type == $extension_types{"server_name"}) {
        parse_server_name_extension($extension_data);
    } elsif ($extension_type == $extension_types{"key_share"}) {
        parse_key_share_extension($extension_data);
    }
}

sub parse_supported_versions_extension {
    my ($extension_data) = @_;

    # struct {
    #     ProtocolVersion versions<2..254>;
    # } SupportedVersions;

    my $supported_versions = substr($extension_data, 0, 2);
    print("SUPPORTED VERSIONS: " . unpack("H*", $supported_versions) . "\n");
    my %reversed_supported_tls_versions = reverse %supported_tls_versions;
    if (!$reversed_supported_tls_versions{unpack("n", $supported_versions)}) {
        die;
        return 0;
    }
}

sub parse_key_share_extension {
    my ($extension_data) = @_;

    # struct {
    #       NamedGroup group;
    #       opaque key_exchange<1..2^16-1>;
    #   } KeyShareEntry;

    # group:  The named group for the key being exchanged.

    # struct {
    #       KeyShareEntry client_shares<0..2^16-1>;
    #   } KeyShareClientHello;

    my $key_share_entry = substr($extension_data, 0, 2);
    print("KEY SHARE ENTRY: " . unpack("H*", $key_share_entry) . "\n");
    my %reversed_supported_key_share_groups = reverse %supported_key_share_groups;
    if (!$reversed_supported_key_share_groups{unpack("n", $key_share_entry)}) {
        die;
        return 0;
    }
    my $key_exchange_length = substr($extension_data, 2, 2);
    my $key_exchange_length_int = unpack("n", $key_exchange_length);
    print("KEY EXCHANGE LENGTH: $key_exchange_length_int\n");
    my $key_exchange = substr($extension_data, 4, $key_exchange_length_int);
    print("KEY EXCHANGE: " . unpack("H*", $key_exchange) . "\n");
    $epoll::clients{fileno($main::client_socket)}{tls}{key_exchange} = $key_exchange;
}

sub parse_change_cipher_spec {
    my ($data, $offest) = @_;

    # An implementation may receive an unencrypted record of type
    # change_cipher_spec consisting of the single byte value 0x01 at any
    # time after the first ClientHello message has been sent or received
    # and before the peer's Finished message has been received and MUST
    # simply drop it without further processing.  Note that this record may
    # appear at a point at the handshake where the implementation is
    # expecting protected records, and so it is necessary to detect this
    # condition prior to attempting to deprotect the record.  An
    # implementation which receives any other change_cipher_spec value or
    # which receives a protected change_cipher_spec record MUST abort the
    # handshake with an "unexpected_message" alert.  If an implementation
    # detects a change_cipher_spec record received before the first
    # ClientHello message or after the peer's Finished message, it MUST be
    # treated as an unexpected record type (though stateless servers may
    # not be able to distinguish these cases from allowed cases).

    my $legacy_record_version = substr($data, $offest+1, 2);
    if ($legacy_record_version ne "\x03\x03") {
        die;
        return 0;
    }
    my $handshake_length = substr($data, $offest+3, 2);
    my $change_cipher_spec = substr($data, $offest+5, 1);
    print("CHANGE CIPHER SPEC: " . unpack("H*", $change_cipher_spec) . "\n");
    print("CHANGE CIPHER SPEC: " . unpack("C", $change_cipher_spec) . "\n");
    if ($change_cipher_spec ne "\x01") {
        die;
        return 0;
    }

    $epoll::clients{fileno($main::client_socket)}{tls}{last_content_type} = 20;
    return $offest + 6;
}

sub parse_application_data {
    my ($data, $offset) = @_;

    print("OFFSET: $offset\n");
    my $application_data;
    my $handshake_length = "";
    if (!$epoll::clients{fileno($main::client_socket)}{tls}{is_continuation}) {
        my $legacy_record_version = substr($data, $offset+1, 2);
        if ($legacy_record_version ne "\x03\x03") {
            die;
            return 0;
        }
        $handshake_length = substr($data, $offset + 3, 2);
        $application_data = substr($data, $offset+ 5, unpack("n", $handshake_length));
    } else {
        $application_data = substr($data, $offset);
    }

    my $client_fd = fileno($main::client_socket);
    my $last_index = scalar keys %{$epoll::clients{$client_fd}{tls}{application_data}};
    if (!$last_index) {
        $last_index = 0;
    }
    if ($epoll::clients{$client_fd}{tls}{is_continuation}) {
        print("ADDING TO LAST INDEX $last_index\n");
        $epoll::clients{$client_fd}{tls}{application_data}{$last_index} .= $application_data;
    } else {
        print("ADDING TO LAST INDEX $last_index+1\n");
        $epoll::clients{$client_fd}{tls}{application_data}{$last_index + 1} = $application_data;
    }

    $epoll::clients{$client_fd}{tls}{last_content_type} = 23;
    return $offset + 5 + unpack("n", $handshake_length);
}


sub get_server_certificate {
    my ($server_hello, $server_hello_size, $complete_data_size) = @_;

    print("SERVER HELLO SIZE: $server_hello_size\n");
    print("COMPLETE DATA SIZE: $complete_data_size\n");
    my $remaining_data = substr($server_hello, $server_hello_size);

    print("REMINING DATA LENGTH: " . length($remaining_data) . "\n");

    my $handshake_content_type = substr($remaining_data, 0, 1);
    print("HANDSHAKE CONTENT TYPE: " . unpack("H*", $handshake_content_type) . "\n");
    print("HANDSHAKE CONTENT TYPE: " . unpack("C", $handshake_content_type) . "\n");
    die;
    # print("REMAINING DATA: " . unpack("H*", $remaining_data) . "\n");
}
1;