#!/usr/bin/perl
use strict;
use warnings;

# Grab the fallback image URL from args
my $placeholder_url = $ARGV[0] || die "Error: Placeholder URL not provided\n";

# Slurp mode: read the entire XML stream at once from STDIN
undef $/;
my $xml_content = <STDIN>;

# Run through every <item> block in the feed
$xml_content =~ s/<item>(.*?)<\/item>/
    my $item_body = $1;
    
    # Check if it's a text-only post (no telegram media links found)
    if ($item_body !~ /https:\/\/(cdn[0-9]*\.telesco\.pe|telesco\.pe)\/file\//) {
        # Slap the default enclosure tag at the end of the item content
        $item_body .= "<enclosure url=\"$placeholder_url\" type=\"image\/jpeg\" length=\"0\" \/>";
    }
    
    # Rebuild the item block
    "<item>" . $item_body . "<\/item>"
/gsme;

# Spit the patched XML back to STDOUT
print $xml_content;
