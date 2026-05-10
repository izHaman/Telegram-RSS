#!/usr/bin/perl
use strict;
use warnings;

my $placeholder_url = $ARGV[0] || die "Missing placeholder\n";

undef $/;
my $xml_content = <STDIN>;

if (defined $xml_content && $xml_content ne "") {
    $xml_content =~ s/<item>(.*?)<\/item>/process_item($1, $placeholder_url)/gse;
    print $xml_content;
}

sub process_item {
    my ($item_body, $placeholder) = @_;
    $item_body =~ s/<enclosure[^>]*>//gi;
    
    if ($item_body =~ m{(https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/main/feeds/media/([a-f0-9]+)\.([a-zA-Z0-9]+))}i) {
        my $url = $1;
        my $user = $2;
        my $repo = $3;
        my $hash = $4;
        my $ext = lc($5);
        
        my $thumb_url = "https://raw.githubusercontent.com/$user/$repo/main/feeds/media/$hash.thumb.jpg";
        my %mimes = ('mp4'=>'video/mp4', 'mp3'=>'audio/mpeg', 'jpg'=>'image/jpeg', 'png'=>'image/png');
        my $mime = $mimes{$ext} || "application/octet-stream";
        
        my $media_html = "";
        
        if ($ext eq "mp4" || $ext eq "mp3") {
            my $label = ($ext eq "mp4") ? "🎥 WATCH VIDEO" : "🎧 LISTEN AUDIO";
            $media_html = <<EOF;
<div style="text-align:center;">
    <img src="$thumb_url" style="width:100%; border-radius:12px;" />
    <div style="margin-top:10px; padding:15px; background:#007bff; border-radius:8px;">
        <a href="$url" style="color:#fff; text-decoration:none; font-weight:bold; display:block;">$label</a>
    </div>
</div>
<br/>
EOF
        } else {
            $media_html = "<img src=\"$url\" style=\"width:100%; border-radius:12px;\" /><br/>";
        }
        
        $item_body =~ s/<description>\s*<!\[CDATA\[/<description><![CDATA[$media_html/;
        return "<item>$item_body<enclosure url=\"$url\" type=\"$mime\" length=\"1024000\" /></item>";
    }
    
    $item_body =~ s/<description>\s*<!\[CDATA\[/<description><![CDATA[<img src="$placeholder" style="width:100%; border-radius:12px;" /><br\/>/;
    return "<item>$item_body<enclosure url=\"$placeholder\" type=\"image/jpeg\" length=\"51200\" /></item>";
}
