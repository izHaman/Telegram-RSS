#!/usr/bin/perl
use strict;
use warnings;

# Professional Media Processor for STC-Reader
# Handles Images, Videos (MP4), and GIFs with high compatibility for RSS Readers like Feeder.

my $placeholder_url = $ARGV[0] || die "Missing placeholder URL\n";

undef $/;
my $xml_content = <STDIN>;

if (defined $xml_content && $xml_content ne "") {
    $xml_content =~ s/<item>(.*?)<\/item>/process_item($1, $placeholder_url)/gse;
    print $xml_content;
}

sub process_item {
    my ($item_body, $placeholder) = @_;
    
    # Remove existing enclosures to prevent duplicates
    $item_body =~ s/<enclosure[^>]*>//gi;
    
    my $enclosure = "";
    my $media_html = "";
    
    # Regex to detect localized GitHub media links
    if ($item_body =~ m{(https://raw\.githubusercontent\.com/[^\s"<]+/feeds/media/([a-f0-9]+\.([a-zA-Z0-9]+))(?:\?[^"\s<]*)?)}i) {
        my $url = $1;
        my $ext = lc($3);
        
        my %mime_types = (
            'mp4'  => 'video/mp4',
            'mkv'  => 'video/x-matroska',
            'mov'  => 'video/quicktime',
            'mp3'  => 'audio/mpeg',
            'jpg'  => 'image/jpeg',
            'jpeg' => 'image/jpeg',
            'png'  => 'image/png',
            'gif'  => 'image/gif',
            'webp' => 'image/webp'
        );
        
        my $mime = $mime_types{$ext} || "application/octet-stream";
        
        if ($mime =~ /^video/) {
            # Standard enclosure for mobile OS integration
            $enclosure = "<enclosure url=\"$url\" type=\"$mime\" length=\"10485760\" />";
            
            # Professional HTML5 Player with fallback link
            # 'playsinline' and 'muted' are critical for mobile RSS readers
            $media_html = <<EOF;
<div style="margin-bottom:15px; background:#000; border-radius:10px; overflow:hidden;">
    <video controls playsinline muted preload="metadata" style="width:100%; display:block;">
        <source src="$url" type="$mime">
        Your app does not support embedded video.
    </video>
    <div style="padding:10px; background:#1a1a1a; text-align:center;">
        <a href="$url" style="color:#00ffcc; text-decoration:none; font-family:sans-serif; font-size:14px; font-weight:bold;">
            ▶️ Play / Download Video
        </a>
    </div>
</div>
EOF
        } else {
            # Standard Image handling
            $enclosure = "<enclosure url=\"$url\" type=\"$mime\" length=\"512000\" />";
            $media_html = "<img src=\"$url\" style=\"width:100%; border-radius:10px; margin-bottom:10px; display:block;\" /><br/>";
        }
    } else {
        # Fallback to visual placeholder for text-only posts
        $enclosure = "<enclosure url=\"$placeholder\" type=\"image/jpeg\" length=\"51200\" />";
        $media_html = "<img src=\"$placeholder\" style=\"width:100%; border-radius:10px; margin-bottom:10px; display:block;\" /><br/>";
    }
    
    # Inject the media HTML at the very beginning of the CDATA description
    $item_body =~ s/<description>\s*<!\[CDATA\[/<description><![CDATA[$media_html/;
    
    return "<item>" . $item_body . $enclosure . "</item>";
}
