#!/usr/bin/perl
use strict;
use warnings;

my $placeholder_url = $ARGV[0] || die "Missing placeholder URL\n";

undef $/;
my $xml_content = <STDIN>;

if (defined $xml_content && $xml_content ne "") {
    $xml_content =~ s/<item>(.*?)<\/item>/process_item($1, $placeholder_url)/gse;
    print $xml_content;
}

sub process_item {
    my ($item_body, $placeholder) = @_;
    
    # Priority: Preserve existing valid enclosures
    return "<item>$item_body</item>" if $item_body =~ /<enclosure/i;
    
    my $enclosure = "";
    
    if ($item_body =~ m{(https://raw\.githubusercontent\.com/[^\s"<]+/feeds/media/([a-f0-9]+\.([a-zA-Z0-9]+))(?:\?[^"\s<]*)?)}i) {
        my $url = $1;
        my $filename = $2;
        my $ext = lc($3);
        
        my %mime_types = (
            'mp4'  => 'video/mp4',
            'mkv'  => 'video/x-matroska',
            'mov'  => 'video/quicktime',
            'mp3'  => 'audio/mpeg',
            'ogg'  => 'audio/ogg',
            'jpg'  => 'image/jpeg',
            'jpeg' => 'image/jpeg',
            'png'  => 'image/png',
            'gif'  => 'image/gif',
            'webp' => 'image/webp'
        );
        
        my $mime = $mime_types{$ext} || "application/octet-stream";
        
        # Video-specific optimization for Feeder and other RSS readers
        if ($mime =~ /^video/) {
            $enclosure = "<enclosure url=\"$url\" type=\"$mime\" length=\"5000000\" />";
            # Injecting a direct video link at the top of description for better compatibility
            $item_body =~ s/<description>\s*<!\[CDATA\[/<description><![CDATA[<p><b>Video Content:<\/b> <a href="$url">Direct Link<\/a><\/p>/;
        } else {
            $enclosure = "<enclosure url=\"$url\" type=\"$mime\" length=\"102400\" />";
        }
    } else {
        $enclosure = "<enclosure url=\"$placeholder\" type=\"image/jpeg\" length=\"51200\" />";
    }
    
    return "<item>" . $item_body . $enclosure . "</item>";
}
