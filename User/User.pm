package User;

use strict;
use warnings;

sub new {
    my ($self, $user_stats) = @_;

    my $uuid = $user_stats->{uuid};
    my $username = $user_stats->{username};
    my $password = $user_stats->{password_hash};
    my $role = $user_stats->{role}; 
    my $email = $user_stats->{email};
    my $human_username = user_utils::decode_uri($username);
    my $displayname = $user_stats->{displayname};
    my $human_displayname = user_utils::decode_uri($user_stats->{displayname});
    # print("Username: $username\n");
    # print("Human username: $human_username\n");
    if (!$username || !$password) {
        # print("Missing username or password\n");
        return 0;
    }
    if (!$role) {
        $role = "user";
    }
    my $User = {
        uuid => $uuid,
        username => $user_stats->{username},
        human_username => $human_username,
        displayname => $user_stats->{displayname},
        human_displayname => user_utils::decode_uri($user_stats->{displayname}),
        role => $user_stats->{role},
        banned => $user_stats->{banned},
        email => $user_stats->{email},
    };

    return $User;
}

1;