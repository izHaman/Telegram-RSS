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
    
    return "<item>$item_body</item>" if $item_body =~ /<enclosure/i;
    
    my $enclosure = "";
    
    if ($item_body =~ m{(https://raw\.githubusercontent\.com/[^\s"<]+/feeds/media/[a-f0-9]+\.([a-zA-Z0-9]+)(?:\?[^"\s<]*)?)}i) {
        my $url = $1;
        my $ext = lc($2);
        my %mime_types = (
            'jpg'  => 'image/jpeg',
            'jpeg' => 'image/jpeg',
            'png'  => 'image/png',
            'gif'  => 'image/gif',
            'webp' => 'image/webp',
            'mp4'  => 'video/mp4',
            'mkv'  => 'video/x-matroska',
            'mp3'  => 'audio/mpeg',
            'ogg'  => 'audio/ogg',
            'pdf'  => 'application/pdf'
        );
        
        my $mime = $mime_types{$ext} || "application/octet-stream";
        $enclosure = "<enclosure url=\"$url\" type=\"$mime\" length=\"102400\" />";
    } else {
        $enclosure = "<enclosure url=\"$placeholder\" type=\"image/jpeg\" length=\"51200\" />";
    }
    
    return "<item>" . $item_body . $enclosure . "</item>";
}
