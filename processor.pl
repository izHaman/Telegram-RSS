#!/usr/bin/perl
use strict;
use warnings;

# Initialize the fallback placeholder URL
my $placeholder_url = $ARGV[0] || die "Critical Error: Missing placeholder URL argument\n";

undef $/;
my $xml_content = <STDIN>;

if (defined $xml_content && $xml_content ne "") {
    $xml_content =~ s/<item>(.*?)<\/item>/process_item($1, $placeholder_url)/gse;
    print $xml_content;
}

sub process_item {
    my ($item_body, $placeholder) = @_;
    
    # Strip existing enclosure tags to rewrite them professionally
    $item_body =~ s/<enclosure[^>]*>//gi;
    
    my $enclosure = "";
    
    # Check for localized GitHub media links
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
            # 1. Standard Enclosure for the system
            $enclosure = "<enclosure url=\"$url\" type=\"$mime\" length=\"10485760\" />";
            
            # 2. Injecting HTML5 Video Player into Description for Feeder compatibility
            # We use a standard video tag that most modern RSS readers support
            my $video_html = <<EOF;
<video controls preload="metadata" style="width:100%; max-height:400px; background:#000; border-radius:8px;">
    <source src="$url" type="$mime">
    Your browser does not support the video tag. <a href="$url">Download Link</a>
</video>
<br/>
EOF
            $item_body =~ s/<description>\s*<!\[CDATA\[/<description><![CDATA[$video_html/;
            
        } else {
            # For images, we just put them at the top
            $enclosure = "<enclosure url=\"$url\" type=\"$mime\" length=\"512000\" />";
            $item_body =~ s/<description>\s*<!\[CDATA\[/<description><![CDATA[<img src="$url" style="width:100%; border-radius:8px; margin-bottom:10px;" \/><br\/>/;
        }
    } else {
        # Fallback to Placeholder if no media is found
        $enclosure = "<enclosure url=\"$placeholder\" type=\"image/jpeg\" length=\"51200\" />";
        $item_body =~ s/<description>\s*<!\[CDATA\[/<description><![CDATA[<img src="$placeholder" style="width:100%; border-radius:8px; margin-bottom:10px;" \/><br\/>/;
    }
    
    return "<item>" . $item_body . $enclosure . "</item>";
}
