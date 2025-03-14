package cookie_utils;

use strict;
use warnings;

use Digest::SHA qw(sha256_hex sha1_hex);
use Time::HiRes qw(gettimeofday);
use Cwd;
use Crypt::CBC;
use MIME::Base64;
use JSON;

# my $key = no_upload::get_cookie_encryption_key();

my $session_timeout = 60*60*3;
my $base_dir = getcwd();
my $session_folder = "$base_dir/Data/Sessions";
if (!-d $session_folder) {
    mkdir($session_folder);
}


sub generate_session_id {
    my ($uuid) = @_;
    my $time = gettimeofday();
    my $random = int(rand(1000000));
    my $id = "$time|$uuid|$random";
    return sha256_hex($id);
}

sub encrypt_cookie {
    my ($data) = @_;
    my $encrypted_data = encryption_utils::encrypt_data($data);
    return encode_base64($encrypted_data, "");
}

sub decrypt_cookie {
    my ($data) = @_;
    my $decoded_data = decode_base64($data);
    return encryption_utils::decrypt_data($decoded_data);
}

sub get_session_cookie {
    my ($username) = @_;
    my $uuid = user_utils::get_uuid_by_username($username);
    my $session_id = generate_session_id($uuid);
    # print("SESSION ID: $session_id\n");
    my $session_data = "$uuid|$session_id";
    my $encrypted_data = encrypt_cookie($session_data);
    my $sessions_file = "$session_folder/sessions.json";
    if (!-e $sessions_file) {
        open(my $fh, '>', $sessions_file) or do {
            warn "Can't open file $sessions_file: $!";
            return;
        };
        print $fh "{}";
        close $fh;
    }
    open my $fh, '<', $sessions_file or do {
        warn "Can't open file $sessions_file: $!";
        return;
    };
    my $json = do { local $/; <$fh> };
    close $fh;
    if (!$json) {
        $json = "{}";
    }
    my $sessions = decode_json($json);
    print("SESSIONS: $sessions\n");
    $sessions->{$session_data} = time() + $session_timeout;
    open $fh, '>', $sessions_file or do {
        warn "Can't open file $sessions_file: $!";
        return;
    };
    print $fh encode_json($sessions);
    close $fh;
    my $cookie = "session=$encrypted_data; HttpOnly; SameSite=Strict; Path=/";
    # print("COOKIE: $cookie\n");
    return $cookie;
}

sub validate_session {
    my ($cookie) = @_;
    if (!$cookie) {
        return 0;
    }

    my $encrypted_data;
    if ($cookie =~ /=([^;]+)/) {
        $encrypted_data = $1;
    }

    if (!$encrypted_data) {
        return 0;
    }

    my $session_data = decrypt_cookie($encrypted_data);
    # print("SESSION_DATA: $session_data\n");
    if (!$session_data) {
        return 0;
    }

    my $sessions_file = "$session_folder/sessions.json";
    if (!-e $sessions_file) {
        return 0;
    }

    open(my $fh, '<', $sessions_file) or do {
        warn "Can't open file $sessions_file: $!";
        return 0;
    };
    my $json = do { local $/; <$fh> };
    close $fh;
    # print("JSON: $json\n");
    if (!$json) {
        return 0;
    }
    my $sessions = decode_json($json);
    
    my $timeout = $sessions->{$session_data};
    if (!$timeout) {
        return 0;
    }

    if ($timeout < time()) {
        return 0;
    }

    $sessions->{$session_data} = time() + $session_timeout;
    
    open $fh, '>', $sessions_file or do {
        warn "Can't open file $sessions_file: $!";
        return 0;
    };
    print $fh encode_json($sessions);
    close $fh;

    my ($uuid, $session_id) = split(/\|/, $session_data);
    # print("UUID: $uuid\n");
    # print("SESSION ID: $session_id\n");
    return ($uuid, $session_id);
}

sub delete_session_cookie {
    my ($cookie) = @_;

    my $encrypted_data;
    if ($cookie =~ /=([^;]+)/) {
        $encrypted_data = $1;
    }

    my $session_data = decrypt_cookie($encrypted_data);
    if (!$session_data) {
        return;
    }
    open my $fh, '<', "$session_folder/sessions.json" or do {
        warn "Can't open file $session_folder/sessions.json: $!";
        return;
    };
    my $json = do { local $/; <$fh> };
    close $fh;
    my $sessions = decode_json($json);
    delete $sessions->{$session_data};
    open $fh, '>', "$session_folder/sessions.json" or do {
        warn "Can't open file $session_folder/sessions.json: $!";
        return;
    };
    print $fh encode_json($sessions);
    close $fh;

}


# sub get_cookie_data {
#     my ($request) = @_;

#     if ($request =~ /Cookie: (.*)/) {
#         my $cookie = $1;
        
#         return read_cookie($cookie);
#     } else {
#         return {};
#     }
# }
# sub read_cookie {
#     my ($cookie) = @_;
#     if (!$cookie) {
#         return;
#     }

#     # print("COOKIE: $cookie\n");
#     if ($cookie =~ /Cookie=(.*==)/s) {
#         $cookie = $1;
#     }
#     my $decrypted_cookie = encryption_utils::decrypt_data($cookie);

#     return decode_json($decrypted_cookie);
# }

# sub extract_id_from_cookie {
#     my ($cookie) = @_;

#     if ($cookie =~ /session=(.*)/) {
#         return $1;
#     }
#     if ($cookie =~ /remember_me=(.*)/) {
#         return $1;
#     }
# }




# sub generate_remember_me_cookie {
#     my (%user_info) = @_;

#     my $fingerprint = $user_info{fingerprint};
#     my $username = $user_info{username};
#     my $ip = $user_info{ip};
#     my $fingerprint_hash = sha256_hex($fingerprint);
#     my %data = (
#         remember_me => $fingerprint_hash,
#         username    => $username,
#         fingerprint => $fingerprint,
#         ip          => $ip,
#         type        => 'remember_me',
#     );
#     my $cookie = create_cookie(%data);
#     my $remember_me_cookies_folder = "$base_dir/RememberMeCookies";
#     if (!-d $remember_me_cookies_folder) {
#         mkdir($remember_me_cookies_folder);
#     }
#     my $remember_me_file = "$remember_me_cookies_folder/$fingerprint_hash";
#     open(my $fh, '>', $remember_me_file) or do {
#         warn "Can't open file $remember_me_file: $!";
#         return;
#     };
#     print $fh "username=$username\n";
#     print $fh "fingerprint=$fingerprint\n";
#     print $fh "ip=$ip\n";
#     close $fh;
#     return "remember_me=$cookie; HttpOnly; Max-Age=31536000; SameSite=Strict; Path=/";
# }

# sub validate_session {
#     my ($cookie_value, $user_info_ref) = @_;

#     my $cookie_data = read_cookie($cookie_value);
#     if (!$cookie_data) {
#         return 0;
#     }
    
#     my $valid_remember_me = generate_remember_me_cookie($user_info_ref);

#     if ($cookie_data->{remember_me} eq $valid_remember_me) {
#         return 1;
#     }

#     return 0;
# }


1;