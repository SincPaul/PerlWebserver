package user_utils;

use strict;
use warnings;
use User::User;
use JSON;
use Cwd;
use URI::Escape;
use Digest::SHA;

my $empty_cookie = "session=; expires=Thu, 01 Jan 1970 00:00:00 GMT";
my $base_dir = getcwd();
my $userdata_folder = "$base_dir/Data/UserData";
sub exist_not_banned {
    my ($client_socket, $uuid) = @_;

    # print("CHECKING USER EXISTS\n");
    if (!user_exists($client_socket, $uuid)) {
        # print("User does not exist\n");
        return 0;
    }
    # print("EXISTS\n");

    if (is_banned($client_socket, $uuid)) {
        # print("User is banned\n");
        return 0;
    }

    # print("USER EXISTS\n");
    return 1;
}

sub user_exists {
    my ($client_socket, $uuid) = @_;

    # print("CHECKING USER EXISTS\n");
    # print("UUID: $uuid\n");
    my $filename = "$userdata_folder/Users/$uuid/$uuid.json";
    if (-e $filename) {
        # print("USER EXISTS\n");
        return 1;
    }
    if (!$client_socket) {
        # print("RETURNING 0\n");
        return 0;
    }
    my $html_body = <<HTML;
    <h1>User does not exist</h1>
    <br>
    <p>Please log in again</p>
    <a href="/login">Login</a>
HTML
    my $html_content = html_structure::get_html($html_body, "User does not exist");
    http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404_WITH_COOKIE($html_content, $cookie::empty_cookie));
    return 0;
}

sub get_username_and_role {
    my ($filename) = @_;
    my $username = get_username_from_filename($filename);

    my $role = get_user_stat($username, "role");

    return ($username, $role);
}

sub get_username_from_filename {
    my ($filename) = @_;
    # print("FILENAME123: $filename\n");
    return substr($filename, 9, -6);
}

sub get_role {
    if ($main::user) {
        # print("User logged in\n");
        return $main::user->{role};
    } else {
        # print("User not logged in\n");
    }
    return undef;  
}

sub get_all_users {
    my ($start_index, $user_per_page) = @_;
    
    if ($main::user) {
        my $role = user_utils::get_role();
        if ($role ne "admin") {
            return 0;
        }
    } else {
        return 0;
    }

    my $total_user_amount = get_user_count();
    my @users = ();
    my $count = 0;
    
    my $base_dir = getcwd();
    foreach my $folder (glob("$userdata_folder/Users/*")) {
        $folder =~ /UserData\/Users\/(.*)/;
        my $uuid = $1;
        my $filename = $folder . "/" . $uuid . ".json";

        if ($count < $start_index) {
            $count++;
            next;
        }

        last if @users >= $user_per_page;

        my ($role) = get_user_stat($uuid, "role");
        my $username = get_username_by_uuid($uuid);
        # print("PUSHING USER: $username\n");
        my $user_hash = {
            uuid => $uuid,
            username => $username,
            role => $role
        };
        push @users, $user_hash;
    }

    return (\@users, $total_user_amount);
}

sub check_if_admin_and_logged_in {
    my ($client_socket) = @_;
    if (!$main::user) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_401("You are not logged in<br><a href=\"/ \">Return to index</a><br><a href=\"/login\">Login</a>"));
        return 0;
    } 
    my $role = get_role();
    if ($role ne "admin") {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_401("You are not an admin<br><a href=\"/ \">Return to index</a><br><a href=\"/login\">Login</a>"));
        return 0;
    }
    else {
        return 1;
    }
}

sub is_banned {
    my ($client_socket, $uuid) = @_;

    my $data = get_json_data($uuid);

    
    if (!$data) {
        return 0;
    }

    if ($data->{banned}->{status} eq "0") {
        return 0;
    }

    if ($data->{banned}->{banned_until} < time()) {
        unban_user($uuid);
        return 0;
    }

    http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_401_WITH_COOKIE("You are banned until " . parse_time($data->{banned}->{banned_until}) . "<br>Reason: " . $data->{banned}->{reason} . "<br><a href=\"/ \">Return to index</a><br><a href=\"/login\">Login</a>", $empty_cookie));
    return 1;
}

sub get_all_roles {
    my @roles = ();
    foreach my $filename (glob("User/Roles/*.pm"))
    {
        # print("FILENAME: $filename\n");
        if ($filename =~ /User\/Roles\/(.*)\./) {
            my $role = $1;
            push @roles, $role;
        } else {
            push @roles, "ERROR FETCHING ROLE";
        }
    }
    return @roles;
}

sub update_user_values {
    my ($uuid, $key, $value) = @_;

    my $filename = "$userdata_folder/Users/$uuid/$uuid.json";
    my $data = get_json_data($uuid);
    # print("UPDATING USER VALUES\n");
    if ($data->{$key}) {
        $data->{$key} = $value;
    } else {
        $data->{$key} = $value;
    }
    # print("DATA: $data\n"); 
    my $json = encode_json($data);
    open(my $file, '>', $filename) or return 0;
    print $file $json;
    close($file);
    return 1;
}

sub get_user_stat {
    my ($uuid, $key) = @_;
    my $data = get_json_data($uuid);
    if (!$data) {
        # print("CANT FETCH DATA FOR $uuid\n");
        return 0;
    }
    if (!$data->{$key}) {
        # print("CANT FETCH DATA FOR $uuid\n");
        return 0;
    }
    # print("DATA: $data->{$key}\n");
    return $data->{$key};
}

sub get_json_data {
    my ($uuid) = @_;
    
    # print("JASN DATA: $uuid\n");
    my $filename = "$userdata_folder/Users/$uuid/$uuid.json";
    open(my $file, '<', $filename) or do {
        # print("Error opening file $filename\n");
        return 0;
    };
    my $json_text = do {
        local $/;
        <$file>
    };
    close($file);
    my $data = eval { decode_json($json_text) };
    if ($@) {
        # print("Error decoding JSON: $@\n");
        return 0;
    }
    return $data;
}

sub get_uuid_by_username {
    my ($username) = @_;
    if (!$username) {
        return 0;
    }
    my $filename = "$userdata_folder/usernames.json";
    open(my $file, '<', $filename) or do {
        # print("Error opening file $filename\n");
        return 0;
    };
    my $json = do { local $/; <$file> };
    close $file;
    my $data = decode_json($json);
    return $data->{user_to_uuid}->{$username};
}

sub get_uuid {
    if ($main::user) {
        return $main::user->{uuid};
    }
    return 0;
}

sub compare_values {
    my ($uuid, $key, $value) = @_;
    my $data = get_json_data($uuid);
    if (!$data) {
        return 0;
    }
    if ($data->{$key} eq $value) {
        return 1;
    }
    return 0;
}

sub ban_user {
    my ($uuid, $reason, $time_until) = @_;

    my $data = get_json_data($uuid);

    if (!$data) {
        return 0;
    }


    $data->{banned}->{status} = "1";
    $data->{banned}->{reason} = $reason;
    $data->{banned}->{banned_until} = $time_until;

    write_json_data($uuid, $data);
}

sub unban_user {
    my ($uuid) = @_;

    my $data = get_json_data($uuid);

    if (!$data) {
        return 0;
    }

    $data->{banned}->{status} = "0";
    $data->{banned}->{reason} = "";
    $data->{banned}->{banned_until} = 0;

    write_json_data($uuid, $data);
}

sub write_json_data {
    my ($uuid, $data) = @_;
    my $filename = "$userdata_folder/Users/$uuid/$uuid.json";
    open(my $file, '>', $filename) or return 0;
    print $file encode_json($data);
    close($file);
    return 1;
}

sub parse_time {
    my ($time) = @_;
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($time);
    
    return sprintf("%02d.%02d.%04d %02d:%02d:%02d", $mday, $mon + 1, $year + 1900, $hour, $min, $sec); 
}

sub is_encoded {
    my ($string) = @_;
    if (!$string) {
        return 0;
    }
    if ($string =~ /%[0-9A-Fa-f]{2}/) {
        return 1;
    }
    return 0;
}

sub decode_uri {
    my ($uri) = @_;
    $uri = uri_unescape($uri);
    return $uri;
}

sub delete_user {
    my ($uuid) = @_;

    if (!$uuid) {
        return 0;
    }
    if (!user_exists(undef, $uuid)) {
        return 0;
    }

    my $role = get_user_stat($uuid, "role");
    if ($role eq "admin") {
        return 0;
    }
    
    my $start_dir = "$base_dir/Data/UserData/Users/$uuid";
    # print("DELETING USER\nStart dir: $start_dir\n");
    if (!delete_files_recursive($start_dir))  {
        # print("Error deleting files\n");
        return 0;
    }

    my $filename = "$userdata_folder/Users/$uuid/$uuid.json";
    unlink($filename);

    remove_from_user_json($uuid);
    return 1;
}

sub remove_from_user_json {
    my ($uuid) = @_;
    my $username = get_username_by_uuid($uuid);
    my $filename = "$userdata_folder/usernames.json";
    open my $file, '<', $filename or return 0;
    my $json = do { local $/; <$file> };
    close $file;
    my $data = decode_json($json);
    # print("JSON: $json\n");
    # print("DATA: $data\n");
    my $uuid_to_user = $data->{uuid_to_user};
    my $user_to_uuid = $data->{user_to_uuid};
    delete $uuid_to_user->{$uuid} or die "Could not delete $uuid from uuid_to_user $!";
    delete $user_to_uuid->{$username} or die "Could not delete $username from user_to_uuid $!";
    open $file, '>', $filename or return 0;
    print $file encode_json($data);
    close($file);
}
sub delete_files_recursive {
    my ($path) = @_;

    opendir(my $dir, $path) or do 
    { 
        # print("Could not open $path $!"); 
        return 0;
    };

    while (my $file = readdir($dir)) {
        if ($file eq "." || $file eq "..") {
            next;
        }
        my $path = "$path/$file";
        if (-d $path) {
            delete_files_recursive($path);
        } else {
            unlink($path);
        }
    }
    # print("Removing $path\n");
    rmdir($path) or die "Could not remove $path $!";
    return 1;
}

sub check_if_user_exists {
    my ($client_socket, $uuid) = @_;
    if (!user_exists($client_socket, $uuid)) {
        my $username = get_username_by_uuid($uuid);
    my $html_body = <<HTML;
    <h1>User $username does not exist</h1>
    <br>
HTML
        $html_body .= admin_utils::return_buttons();
        my $html_content = html_structure::get_html($html_body, "User does not exist");
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404($html_content));
        return 0;
    }
    return 1;
}

sub encode_uri {
    my ($uri) = @_;
    $uri = uri_escape_utf8($uri);
    return $uri;
}


sub get_user_count {
    my $count = 0;
    # print("COUNTING USERS\n");

    foreach my $folder (glob("$userdata_folder/Users/*")) {
        $count++;
    }
    return $count;
}

sub get_uploads {
    my @uploads = ();
    if (!$main::user) {
        return 0;
    }
    my $data_path = "$userdata_folder/Users/$main::user->{uuid}/ploud";

    foreach my $file (glob("$data_path/*")) {
        
        if (!-d $file) {
            next;
        }
        # print("FILE: $file\n");
        my $filename = $file;
        $filename =~ s/$data_path\///;
        # print("DATA_PATH: $data_path\n");
        # print("FILENAME: $filename\n");
        push @uploads, $filename;
    }
    return @uploads;
}

sub get_metadata {
    my ($filename) = @_;
    # print("METADATACHECK: $filename\n");
    my $data_path = "$userdata_folder/Users/$main::user->{uuid}/ploud/$filename/metadata.json";
    open(my $file, '<', $data_path) or return 0;
    # print("OPENED FILE: $file\n");
    my $json = <$file>;
    # print("JSON: $json\n");
    close $file;
    if (!$json) {
        return 0;
    }
    my $metadata = decode_json($json);
    # print("METADATA: $metadata\n");
    return $metadata;
}

sub format_bytes {
    my ($bytes) = @_;
    if ($bytes eq "Unknown") {
        return "Unknown";
    }
    if ($bytes >= 1024 * 1024 * 1024) {
        return sprintf("%.2f GB", $bytes / (1024 * 1024 * 1024));
    } elsif ($bytes >= 1024 * 1024) {
        return sprintf("%.2f MB", $bytes / (1024 * 1024));
    } elsif ($bytes >= 1024) {
        return sprintf("%.2f KB", $bytes / 1024);
    } else {
        return "$bytes B";
    }
}

sub get_current_used_storage {
    my ($uuid) = @_;

    # print("GETTING USED STORAGE\n");
    if (!user_exists(undef, $uuid)) {
        return 0;
    }
    my $used_storage = 0;
    # print("GETTING USED STORAGE\n");
    my $data_path = "$userdata_folder/Users/$uuid/ploud/usermetadata.json";
    if (!-e $data_path) {
        # print("File does not exist: $data_path\n");
        return 0;
    }
    if (!-r $data_path) {
        # print("File is not readable: $data_path\n");
        return 0;
    }
    open(my $file, '<', $data_path) or do {
        # print("Error opening file $data_path: $!\n");
        return 0;
    };
    my $json = <$file>;
    close $file;
    if (!$json) {
        return 0;
    }
    my $data = decode_json($json);
    # print("USERMETADATA: $data\n");
    # print("DATA: $data\n");
    $used_storage = $data->{used_storage};
    return $used_storage;
}

sub get_user_max_storage {
    my ($uuid) = @_;

    my $user_stats = user_utils::get_json_data($uuid);
    if (!$user_stats) {
        return "User not found";
    }
    my $max_storage = $user_stats->{rank}{benefits}{max_storage};
    if (!$max_storage) {
        $max_storage = $main::max_storage
    }
    return $max_storage;
}
sub update_user_metadata {
    my ($uuid, $data) = @_;
    my $filename = "$userdata_folder/Users/$uuid/ploud/usermetadata.json";
    my $current_storage = 0;
    my $metadata;

    # print("FILENAME: $filename\n");
    # print("UPDATIN METADATA: $data->{size}\n");

    open (my $file, '<', $filename) or do {
        # print("Error opening file $filename\n");
    };
    my $json = <$file>;
    close $file;
    if ($json) {
        $metadata = decode_json($json);
        $current_storage = $metadata->{used_storage};
    }
    if ($data->{subtract}) {
        $current_storage -= $data->{size};
    } else {
        $current_storage += $data->{size};
    }
    $metadata->{used_storage} = $current_storage;


    open($file, '>', $filename) or return 0;
    print $file encode_json($metadata);
    close($file);
    return 1;
}

sub get_rank_stats {
    my ($rank_id, $key) = @_;

    my $filename = "Utils/ranks.json";

    open(my $file, '<', $filename) or do {
        # print("Error opening file $filename\n");
        return 0;
    };

    my $json = do { local $/; <$file> };
    close $file;
    my $data = decode_json($json);

    

    return $data->{$rank_id}->{$key};

}

sub get_rank_id {
    my ($rank) = @_;

    my $filename = "Utils/ranks.json";

    open(my $file, '<', $filename) or do {
        # print("Error opening file $filename\n");
        return 0;
    };

    my $json = do { local $/; <$file> };
    close $file;
    my $data = decode_json($json);

    foreach my $rank_id (keys %$data) {
        if ($data->{$rank_id}->{name} eq $rank) {
            return $rank_id;
        }
    }
    return 0;
}

sub update_rank_stats {
    my ($uuid, $key, $value) = @_;

    my $userdata = get_json_data($uuid);

    if (!$userdata) {
        return 0;
    }

    my $rank_data = $userdata->{rank};
    if (!$rank_data) {
        serve_error(HTTP_RESPONSE::ERROR_500("Could not fetch rank data"));
        return 0;
    }
    if ($key eq "max_storage" || $key eq "storage_used") {
        # print("UPDATING RANK BENEFITS\n");
        # print("KEY: $key\n");
        # print("VALUE: $value\n");
        # print("UPDATING $userdata->{rank}{benefits}{$key} TO $value\n");
        $userdata->{rank}{benefits}{$key} = $value;
    } else {
        $userdata->{rank}{$key} = $value;
    }

    open (my $file, '>', "$userdata_folder/Users/$uuid/$uuid.json") or return 0;
    print $file encode_json($userdata);
    close($file);
    return 1;
}

sub read_file {
    my ($filename) = @_;
    $filename =~ s|\\|/|g;
    $filename =~ s/\r\n$//; 
    $filename =~ s/\n$//;
    $filename =~ s/\r$//;
    # print("FILENAME: $filename HELLO");
    open(my $file, '<', $filename) or do {
        # print("Error opening file $filename: $!\n");
        return 0;
    };
    my $content = do { local $/; <$file> };
    close $file;
    return $content;
}

sub write_file {
    my ($filename, $content) = @_;
    open(my $file, '>', $filename) or do {
        # print("Error opening file $filename\n");
        return 0;
    };
    print $file $content;
    close $file;
    return 1;
}

sub create_random_string {
    my ($length) = @_;

    my @chars = ('a'..'z', 'A'..'Z', '0'..'9');
    my $string = join '', @chars[ map { rand @chars } 1..$length ];
    return $string;
}

sub populate_user {
    my ($cookie) = @_;

    # print("POPULATING USER\n");
    # print("COOKIE: $cookie\n");
    # my $cookie_data = cookie_utils::read_cookie($cookie);
    my ($uuid, $session_id) = cookie_utils::validate_session($cookie);
    if (!$uuid || !$session_id) {
        # print("Invalid cookie\n");
        return 0;
    }

    my $user_stats = get_user_stats($uuid);
    if (!$user_stats) {
        # print("No user stats found\n");
        return;
    }
    # print("USER STATS: $user_stats\n");
    # foreach my $key (keys %$user_stats) {
        # print("KEY: $key\n");
        # print("VALUE: $user_stats->{$key}\n");
    # }
    # print("creating User\n");
    $main::user = User->new($user_stats);
}

sub get_username_by_uuid {
    my ($uuid) = @_;
    my $filename = "$userdata_folder/usernames.json";
    open(my $file, '<', $filename) or do {
        # print("Error opening file $filename\n");
        return 0;
    };
    my $json = do { local $/; <$file> };
    close $file;
    my $data = decode_json($json);
    return $data->{uuid_to_user}->{$uuid};
}

sub get_user_stats {
    my ($uuid) = @_;
    my $filename = "$userdata_folder/Users/$uuid/$uuid.json";

    if (-e $filename) {
        open(my $file, '<', $filename) or return 0;
        my $json = do { local $/; <$file>};
        close $file;
        my $user_stats = decode_json($json);
        # print("USER STATS: $user_stats\n");
        # foreach my $key (keys %$user_stats) {
            # print("KEY: $key\n");
            # print("VALUE: $user_stats->{$key}\n");
        # }
        return $user_stats;
    }
}

sub round_up {
    my ($number) = @_;

    if ($number == int($number)) {
        return $number;
    }
    return int($number + 0.5);
}

sub get_server_storage {
    my $path = "/home/";

    my $total = `df $path`;

    # print("TOTAL: $total\n");
    my %storage = ();
    if ($total =~/^.+?\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d+%)\s+\S+$/) {
        $storage{mount} = $1;
        $storage{total} = $2 * 1024;
        $storage{used} = $3 * 1024;
        $storage{free} = $4 * 1024;
        $storage{used_percentage} = $5;
    } else {
        return 0;
    }
    return \%storage;

}

sub get_server_storage_json {
    my $storage = get_server_storage();
    return encode_json($storage);
}

sub hash_password {
    my ($password) = @_;
    # print("PASSWORD: $password\n");
    my $salt = create_random_string(16);          
    my $hash = crypt($password, "\$6\$$salt");    
    return $hash;                                 
}

sub verify_password {
    my ($entered_password, $stored_hash) = @_;
    # print("STORED HASH:  $stored_hash\n");
    my $entered_hash = crypt($entered_password, $stored_hash);
    # print("ENTERED HASH: $entered_hash\n");
    return $entered_hash eq $stored_hash;                     
}


sub is_wide {
    my ($string) = @_;
    
    # print("STRING: $string\n");
    foreach my $char (split //, $string) {
        # print("CHAR: $char\n");
        if ($char =~ /[^\x00-\x7F]/) {
            # print("WIDE CHARACTER DETECTED: $char\n");
            return 1;
        }
    }
}

sub is_email_verified {
    if (!$main::user) {
        return 0;
    }
    my $email_status = get_user_stat($main::user->{uuid}, "email_status");
    if ($email_status eq "verified") {
        return 1;
    }
    return 0;
}

sub get_used_emails {
    my $filename = "$userdata_folder/used_emails.json";
    if (!-e $filename) {
        open my $file, '>', $filename or do {
            # print("Error opening file $filename\n");
            return 0;
        };
    }
    open(my $file, '<', $filename) or do {
        # print("Error opening file $filename\n");
        return 0;
    };
    my $json = do { local $/; <$file> };
    close $file;
    if (!$json) {
        return {};
    }
    my $data = decode_json($json);
    return $data;
}

sub save_used_emails {
    my ($data) = @_;
    my $filename = "$userdata_folder/used_emails.json";
    open(my $file, '>', $filename) or do {
        # print("Error opening file $filename\n");
        return 0;
    };
    print $file encode_json($data);
    close($file);
}

sub get_displayname_by_uuid {
    my ($uuid) = @_;
    my $username = get_username_by_uuid($uuid);
    my $displayname = get_user_stat($uuid, "displayname");
    if ($displayname) {
        return $displayname;
    }
    return $username;
}

sub get_subscribed_to {
    my $filename = "$userdata_folder/Users/$main::user->{uuid}/Streaming/OtherPeopleInfo/subscribed_to.txt";
    if (!-e $filename) {
        return;
    }
    my @subscribed_to;
    open my $file, '<', $filename;
    while (my $line = <$file>) {
        print("LINE: $line\n");
        chomp $line;
        push @subscribed_to, $line;
    }
    close $file;
    return @subscribed_to;
}

sub get_users {
    my ($fragment) = @_;

    my @possible_users;

    my $skip;
    my $displaynames_file = "$userdata_folder/displaynames.json";
    if (!-e $displaynames_file) {
        $skip = 1;
    }

    if (!$skip) {
        open my $file, '<', $displaynames_file;
        my $json = do { local $/; <$file> };
        close $file;
        my $data = decode_json($json);
        my $displaynames = $data->{displaynames};

        foreach my $displayname (keys %$displaynames) {
            if ($displayname =~ /$fragment/) {
                foreach my $uuid (@{$displaynames->{$displayname}}) {
                    my $username = get_username_by_uuid($uuid);
                    my %user = (
                        username => $username,
                        displayname => $displayname,
                        uuid => $uuid
                    );
                    push @possible_users, \%user;
                }
            }
        }
    } 

    my $usernames_file = "$userdata_folder/usernames.json";
    if (!-e $usernames_file) {
        return;
    }
    open my $file, '<', $usernames_file;
    my $json = do { local $/; <$file> };
    close $file;
    my $data = decode_json($json);
    my $user_to_uuid = $data->{user_to_uuid};
    foreach my $username (keys %$user_to_uuid) {
        my $displayname = get_displayname_by_uuid($user_to_uuid->{$username});
        if ($username =~ /$fragment/) {
            my %user = (
                username => $username,
                displayname => $displayname,
                uuid => $user_to_uuid->{$username}
            );
            push @possible_users, \%user;
        }
    }

    return @possible_users;

}

sub random_number {
    my ($amount) = @_;

    my $number;
    for (my $i = 0; $i < $amount; $i++) {
        $number .= int(rand(10));
    }
    return $number;
}

sub create_file_hash {
    my ($hash_algorithm, $filepath) = @_;

    print("FILEPATH: $filepath\n");
    open(my $file, '<', $filepath) or die "Cannot open file: $!";
    binmode($file);

    my $hash = Digest::SHA->new($hash_algorithm) or die "Unknown algorithm: $hash_algorithm";
    my $buffer;
    while (read($file, $buffer, 4096)) {
        $hash->add($buffer);
    }
    close($file);

    return $hash->hexdigest;
}

sub is_int {
    my ($number) = @_;
    if ($number =~ /^\d+$/) {
        return 1;
    }
    return 0;
}
1;