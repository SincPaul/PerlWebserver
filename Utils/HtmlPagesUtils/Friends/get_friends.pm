package get_friends;

use strict;
use warnings;


my %request_types = (
    "received" => \&friend_utils::get_received_requests,
    "sent" => \&friend_utils::get_sent_requests,
);

sub get_friend_requests {
    my ($client_socket, $route) = @_;

    if (!$main::user) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_401("Unauthorized"));
        return;
    }

    my ($request_type) = $route =~ /\/friends\/requests\/(.+)/;
    print("REQUEST TYPE: $request_type\n");
    if (!exists $request_types{$request_type}) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_400("Bad Request"));
        return;
    }

    return $request_types{$request_type}->($client_socket, $route);
}

sub get_friends {
    my ($client_socket, $route) = @_;

    if (!$main::user) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_401("Unauthorized"));
        return;
    }

    my $friends = friend_utils::get_friends($client_socket, $main::user->{uuid});
    print("FRIEND1: $friends\n");
    http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK_WITH_DATA($friends, "friends.json"));
    print("SENT FRIENDS\n");
    # http_utils::send_http_response(HTTP_RESPONSE::OK_WITH_DATA(friend_utils::get_friends($client_socket, $main::user->{uuid}), "friends.json"));
}

sub get_blocked_users {
    my ($client_socket, $route) = @_;

    if (!$main::user) {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_401("Unauthorized"));
        return;
    }

    return friend_utils::get_blocked_users($client_socket, $route);
}
1;