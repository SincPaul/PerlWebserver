package load_js;

use strict;
use warnings;

use Cwd;

sub get_external_js {
    my ($client_socket, $request) = @_;

    print("REQUEST: $request\n");
    $request = lc $request;
    if ($request =~ /\/externaljs\/(.*)/) {
        my $filename = $1;
        print("FILENAME: $filename\n");
        my $base_dir = getcwd();
        my $file_path = "$base_dir/Data/ExternalJS/$filename";
        if (-e $file_path) {
            open my $fh, '<', $file_path or die "Cannot open file: $!";
            binmode $fh;
            my $file_data;
            {
            local $/;
            $file_data = <$fh>;
            }
            close $fh;
            http_utils::send_http_response($client_socket, HTTP_RESPONSE::OK_JS_WITH_CACHE($file_data));
        } else {
            
            print("FILE NOT FOUND\n");
            http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("File not found"));
        }
    } else {
        http_utils::serve_error($client_socket, HTTP_RESPONSE::ERROR_404("File not found"));
    }
}

1;