package logout_user;

use strict;
use warnings;

sub get_logout {
    my ($client_socket) = @_;
    handle_logout($client_socket);
}

sub handle_logout {
    my ($client_socket) = @_;
    cookie_utils::delete_session_cookie(request_utils::get_session_cookie($main::header));
    my $html = get_operation_finished_pages::get_logout_html();
    my $response = HTTP_RESPONSE::OK_WITH_COOKIE($html, $cookie::empty_cookie);
    http_utils::send_http_response($client_socket, $response);
}

1;