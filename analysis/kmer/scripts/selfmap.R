library( argparse )
library( RSQLite )
RESOURCEDIR=Sys.getenv( "MG_RESOURCEDIR" )
ANALYSISDIR=Sys.getenv( "MG_ANALYSISDIR" )
PROJECTDIR=Sys.getenv( "MG_PROJECTDIR" )
source( sprintf( "%s/library/R/scripts/shared_functions.R", RESOURCEDIR ))

#############################
# Declare options
{
	parser <- ArgumentParser( description = 'Compare two genomes' )
	parser$add_argument(
		"--s1",
		type = "character",
		help = "First sequence file, in format name=<filename>",
		required = TRUE
	)
	parser$add_argument(
		"--chromosome1",
		type = "character",
		help = "Chromosome identifier of first sequence file (to match genes)",
		required = TRUE
	)
	parser$add_argument(
		"--genes1",
		type = "character",
		help = "First genes file",
		default = "/well/longread/projects/reference/GRCh37/UCSC/2019-08-27-GRCh37-wgEncodeGencodeBasicV19.tsv"
	)
	parser$add_argument(
		"--s2",
		type = "character",
		help = "Second sequence file, in format name=<filename>",
		required = TRUE
	)
	parser$add_argument(
		"--chromosome2",
		type = "character",
		help = "Chromosome identifier of second sequence file (to match genes)",
		required = TRUE
	)
	parser$add_argument(
		"--genes2",
		type = "character",
		help = "Second genes file",
		default = "/well/longread/projects/reference/GRCh38/UCSC/2019-08-27-GRCh38-wgEncodeGencodeBasicV31.tsv"
	)
	parser$add_argument(
		"--k",
		type = "integer",
		help = "k-mer size for upper panel",
		default = 100
	)
	parser$add_argument(
		"--range1",
		type = "character",
		help = "Range in sequence 1 to plot"
	)
	parser$add_argument(
		"--range2",
		type = "character",
		help = "Range in sequence 2 to plot"
	)
	parser$add_argument(
		"--output",
		type = "character",
		help = "Path to output file"
	)
}

opts = parser$parse_args()

cat( "Options are:\n" )
print( opts )

#############################
# Load data

load.genes = function( filename, condense = TRUE, protein.coding.only = TRUE ) {
	if( is.null( filename )) {
		return(
			data.frame(
				chrom = c(),
				txStart = c(),
				txEnd = c(),
				name2 = c(),
				chromosome = c()
			)
		)
	}
	# Load genes
	gene <- read.delim(
	filename,
		header=TRUE,
		as.is=TRUE
	);
	
	if( condense ) {
		gene <- gene[order(gene$txEnd - gene$txStart,decreasing=TRUE),];  #Get just longest transcript
		gene <- gene[ !duplicated( gene$name2 ), ];
	}
	gene <- gene[ !is.na(gene$txStart), ];
	
	if( protein.coding.only ) {
		gene <- gene[ gene$cdsStart != gene$cdsEnd, ]
	}
	
	chromosome =  gsub( "^chr", "", gene$chrom )
	w1 = which( nchar( chromosome ) == 1 )
	chromosome[ w1 ] = sprintf( "0%s", chromosome[w1] )
	gene$chromosome = chromosome
	return( gene ) ;
}

geneLists = list(
	'GRCh37' = "/well/longread/projects/reference/GRCh37/UCSC/2019-08-27-GRCh37-wgEncodeGencodeBasicV19.tsv",
	'GRCh38' = "/well/longread/projects/reference/GRCh38/UCSC/2019-08-27-GRCh38-wgEncodeGencodeBasicV31.tsv"
)


sequence1 = strsplit( opts$s1, split = '=' )[[1]]; names( sequence1 ) = c( "name", "filename" )
sequence2 = strsplit( opts$s2, split = '=' )[[1]]; names( sequence2 ) = c( "name", "filename" )

if( is.null( opts$genes1 )) {
	opts$genes1 = geneLists[[sequence1['name'] ]]
}
if( is.null( opts$gene2 )) {
	if( sequence2['name'] %in% names( geneLists ) ) {
		opts$genes2 = geneLists[[sequence2['name'] ]]
	}
}

cat( "Loading genes...\n" )
genes = list(
	first = load.genes( opts$genes1 ),
	second = load.genes( opts$genes2 )
)

run.selfmap <- function( sequence1, sequence2, k, chromosome1, chromosome2 ) {
	output = tempfile()
	cmd = sprintf( 'selfmap_v2.1-dev -sequence %s=%s %s=%s -kmer-size %d -o %s',
		sequence1['name'], sequence1['filename'],
		sequence2['name'], sequence2['filename'], k, output
	)
	cat( "Running \"", cmd, "\"...\n", sep = '' )
	system( cmd )
	cat( "Loading \"", output, "\"...\n", sep = '' )
	X = read.table( output, hea=T, as.is=T )
	X = X[ grep( sprintf( "^%s:", sequence1['name'] ), X$chromosome ), ]
	X = X[ grep( sprintf( "^%s:", sequence2['name'] ), X$other_chromosome ), ]
	X$chromosome = chromosome1
	X$other_chromosome = chromosome2
	cat( "...ok, read:\n" )
	print( head( X ))
	return(X)
}
cat( "Computing shared k-mers...\n" )
X1 = run.selfmap( sequence1, sequence2, opts$k, fix_chromosome( opts$chromosome1 ), fix_chromosome( opts$chromosome2 ))
X2 = run.selfmap( sequence1, sequence2, opts$k / 2, fix_chromosome( opts$chromosome1 ), fix_chromosome( opts$chromosome2 ))

if( !is.null( opts$range1 )) {
	range1 = parse_ranges( opts$range1 )
} else {
	range1 = data.frame(
		chromosome = opts$chromosome1,
		start = min( c( X1$position )),
		end = max( c( X1$position ) + opts$k )
	)
}

if( !is.null( opts$range2 )) {
	range2 = parse_ranges( opts$range2 )
} else {
	range2 = data.frame(
		chromosome = opts$chromosome1,
		start = min( c( X1$other_position )),
		end = max( c( X1$other_position ) + opts$k )
	)
}

myGrid <- function( main.divisions = 1, sub.divisions = 4,	main.col = "grey40", sub.col = "grey80", lty = 3, horiz = TRUE, vert = TRUE ) {
	xaxp = par( "xaxp" )
	yaxp = par( "yaxp" )
	if( horiz ) {
		abline( h = seq( from = yaxp[1], to = yaxp[2], length = (sub.divisions*yaxp[3]+1)), col = sub.col, lty = lty )
		abline( h = seq( from = yaxp[1], to = yaxp[2], length = (main.divisions*yaxp[3]+1)), col = main.col, lty = lty )
	}
	if( vert ) {
		abline( v = seq( from = xaxp[1], to = xaxp[2], length = (sub.divisions*xaxp[3]+1)), col = sub.col, lty = lty )
		abline( v = seq( from = xaxp[1], to = xaxp[2], length = (main.divisions*xaxp[3]+1)), col = main.col, lty = lty )
	}
}

#############################
# Plot


X1$col = 'black'
X1$col[ which( X1$other_orientation == '-' )] = 'red'
X1$pch = '.'

X2$col = 'grey'
X2$col[ which( X2$other_orientation == '-' )] = 'indianred2'


for( i in 1:1 ) {
	chromosomes = c(
		fix_chromosome( as.character( range1$chromosome[i] ) ),
		fix_chromosome( as.character( range2$chromosome[i] ) )
	)
	region_names = c(
		sprintf( "%s: %s:%d-%d", sequence1['name'], chromosomes[1], range1$start[i], range1$end[i] ),
		sprintf( "%s: %s:%d-%d", sequence2['name'], chromosomes[2], range2$start[i], range2$end[i] )
	)

	data = list(
		X2[
			which(
				X2$chromosome == chromosomes[1] & X2$position >= range1$start[1] & X2$position <= range1$end[i]
				& X2$other_chromosome == chromosomes[2] & X2$other_position >= range2$start[i] & X2$other_position <= range2$end[i]
			),
		],
		X1[
			which(
				X1$chromosome == chromosomes[1] & X1$position >= range1$start[1] & X1$position <= range1$end[i]
				& X1$other_chromosome == chromosomes[2] & X1$other_position >= range2$start[i] & X1$other_position <= range2$end[i]
			),
		]
	)
	names(data) = sprintf( "k=%d", c( as.integer(opts$k/2), as.integer(opts$k )))

	pdf( file = opts$output, width = 8, height = 8 )
	layout( matrix( c( 1, 2, 3, 4 ), nrow = 2, ncol = 2 ), heights = c( 5, 2 ), widths = c( 5.3, 2 ))
	par( mar = c( 2, 2, 2, 1 ))

	# Dot plot

	# Upper dot plot
	plot(
		0, 0, col = 'white', 
		xlab = region_names[1],
		ylab = region_names[2],
		xaxt="n",
		xlim = c( range1$start, range1$end ),
		ylim = c( range2$start, range2$end )
	)
	for( j in 1:length( data )) {
		points(
			data[[j]]$position, data[[j]]$other_position,
			pch = '.', col = data[[j]]$col
		)
	}
	legend( "topleft", bty = 'n', legend = names( data ), pch = 19, col = sapply( 1:length(data), function(k) { data[[k]]$col[1] } ))
	axis( side = 3 )
	axis( side = 2 )
	axis( side = 1 )
	
	# Lower dot plot
	#points( XL$other_position, XL$position, pch = '.', col = XL$col )

	# grid
	#abline( a = 0, b = 1, col = "grey" )
	myGrid( main.col = "grey10", sub.col = "grey50" )


	# genes
	{
		par( mar = c( 2, 2, 0, 1 ), xaxt = 's', bty = 'o' )
		plot.genes( chromosomes[1], c( range1$start, range1$end ), genes[[1]], height_in_inches = 2 )
		myGrid( horiz = FALSE, main.col = "grey10", sub.col = "grey80" )

		par( mar = c( 2, 0, 2, 2 ), xaxt = 'n', yaxt = 'n', bty = 'o' )
		plot.genes( chromosomes[2], c( range2$start, range2$end ), genes[[2]], height_in_inches = 2, vertical = T )
		axis( side = 4 )
		myGrid( vert = FALSE, main.col = "grey10", sub.col = "grey80" )
	}

	dev.off()
}



