#!/usr/bin/perl
use strict;
use warnings;

my $placeholder_url = $ARGV[0] || die "Error: Placeholder URL not provided\n";

undef $/;
my $xml_content = <STDIN>;

$xml_content =~ s/<item>(.*?)<\/item>/
    my $item_body = $1;
    my $enclosure = "";
    
    # Did bash inject our github raw link into this post?
    if ($item_body =~ m{(https:\/\/raw\.githubusercontents?\.com\/[^\/]+\/[^\/]+\/main\/feeds\/images\/([^"<\s\?]+)(?:\?v=\d+)?)[^"<\s]*}) {
        my $full_url = $1;
        my $filename = $2;
        
        # Extract the true extension built by bash
        my $ext = "";
        if ($filename =~ m/\.([a-zA-Z0-9]+)$/) {
            $ext = lc($1);
        }
        
        # Route to proper MIME type for Feeder player
        my $mime = "application/octet-stream";
        if ($ext =~ m/^(mp4|mkv|avi)$/) { $mime = "video\/mp4"; }
        elsif ($ext =~ m/^(mp3|m4a|wav)$/) { $mime = "audio\/mpeg"; }
        elsif ($ext =~ m/^(ogg|oga)$/) { $mime = "audio\/ogg"; }
        elsif ($ext =~ m/^(jpg|jpeg)$/) { $mime = "image\/jpeg"; }
        elsif ($ext eq "png") { $mime = "image\/png"; }
        elsif ($ext eq "gif") { $mime = "image\/gif"; }
        elsif ($ext eq "webp") { $mime = "image\/webp"; }
        
        # Readers often ignore length="0", so we spoof a generic valid length
        $enclosure = "<enclosure url=\"$full_url\" type=\"$mime\" length=\"150000\" \/>";
    } else {
        # Text-only post gets the default blurred image
        $enclosure = "<enclosure url=\"$placeholder_url\" type=\"image\/jpeg\" length=\"50000\" \/>";
    }
    
    "<item>" . $item_body . $enclosure . "<\/item>"
/gsme;

print $xml_content;
