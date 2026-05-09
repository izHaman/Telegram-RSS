#!/usr/bin/perl
use strict;
use warnings;

# Initialize the fallback placeholder URL provided via command-line arguments
my $placeholder_url = $ARGV[0] || die "Critical Error: Missing placeholder URL argument\n";

# Read the entire standard input (XML content) into memory
undef $/;
my $xml_content = <STDIN>;

# Process the XML content if it is valid and non-empty
if (defined $xml_content && $xml_content ne "") {
    # Extract and process each <item> node individually using the regex evaluation modifier
    $xml_content =~ s/<item>(.*?)<\/item>/process_item($1, $placeholder_url)/gse;
    print $xml_content;
}

sub process_item {
    my ($item_body, $placeholder) = @_;
    
    # Strip existing <enclosure> tags completely to prevent conflicts with custom media logic
    $item_body =~ s/<enclosure[^>]*>//gi;
    
    my $enclosure = "";
    
    # Verify if the bash script successfully injected a GitHub raw media URL
    if ($item_body =~ m{(https://raw\.githubusercontent\.com/[^\s"<]+/feeds/media/([a-f0-9]+\.([a-zA-Z0-9]+))(?:\?[^"\s<]*)?)}i) {
        my $url = $1;
        my $filename = $2;
        my $ext = lc($3);
        
        # Map file extensions to their corresponding MIME types
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
        
        # Apply specific formatting for video content to ensure cross-reader compatibility
        if ($mime =~ /^video/) {
            $enclosure = "<enclosure url=\"$url\" type=\"$mime\" length=\"5000000\" />";
            # Inject a direct video hyperlink at the beginning of the CDATA description block
            $item_body =~ s/<description>\s*<!\[CDATA\[/<description><![CDATA[<p><b>Video Content:<\/b> <a href="$url">Direct Link<\/a><\/p>/;
        } else {
            $enclosure = "<enclosure url=\"$url\" type=\"$mime\" length=\"102400\" />";
        }
    } else {
        # Fallback Sequence: Executed if no valid media URL is detected (text-only post or failed download)
        
        # 1. Define the default placeholder as the primary enclosure
        $enclosure = "<enclosure url=\"$placeholder\" type=\"image/jpeg\" length=\"51200\" />";
        
        # 2. Inject the placeholder image directly into the HTML description for maximum visibility
        $item_body =~ s/<description>\s*<!\[CDATA\[/<description><![CDATA[<img src="$placeholder" style="width:100%; border-radius:8px; margin-bottom:10px;" \/><br\/>/;
    }
    
    # Reconstruct and return the finalized <item> block
    return "<item>" . $item_body . $enclosure . "</item>";
}
