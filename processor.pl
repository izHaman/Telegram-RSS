#!/usr/bin/perl
use strict;
use warnings;

# Retrieve the default fallback image URL
my $placeholder_url = $ARGV[0] || die "Error: Placeholder URL not specified\n";

# Read the entire XML stream from STDIN
undef $/;
my $xml_content = <STDIN>;

if (defined $xml_content && $xml_content ne "") {
    # Parse each item block safely using a clean subroutine
    $xml_content =~ s/<item>(.*?)<\/item>/process_item($1, $placeholder_url)/gse;
    print $xml_content;
}

# Subroutine to safely isolate processing logic per item
sub process_item {
    my ($item_body, $placeholder) = @_;
    my $enclosure = "";
    
    # Check if a GitHub raw media link was injected into this item
    if ($item_body =~ m{(https:\/\/raw\.githubusercontent\.com\/[^\/]+\/[^\/]+\/main\/feeds\/images\/[a-f0-9]+\.([a-zA-Z0-9]+))}i) {
        my $url = $1;
        my $ext = lc($2);
        my $mime = "application/octet-stream";
        
        # Determine the accurate MIME type based on file extension
        if ($ext =~ /^(jpg|jpeg)$/) { $mime = "image/jpeg"; }
        elsif ($ext eq "png") { $mime = "image/png"; }
        elsif ($ext eq "gif") { $mime = "image/gif"; }
        elsif ($ext eq "webp") { $mime = "image/webp"; }
        elsif ($ext eq "mp4") { $mime = "video/mp4"; }
        elsif ($ext eq "mkv") { $mime = "video/x-matroska"; }
        elsif ($ext eq "mp3") { $mime = "audio/mpeg"; }
        elsif ($ext eq "ogg") { $mime = "audio/ogg"; }
        elsif ($ext eq "pdf") { $mime = "application/pdf"; }
        
        $enclosure = "<enclosure url=\"$url\" type=\"$mime\" length=\"102400\" />";
    } else {
        # Fall back to the default image for text-only posts
        $enclosure = "<enclosure url=\"$placeholder\" type=\"image/jpeg\" length=\"51200\" />";
    }
    
    return "<item>" . $item_body . $enclosure . "</item>";
}
