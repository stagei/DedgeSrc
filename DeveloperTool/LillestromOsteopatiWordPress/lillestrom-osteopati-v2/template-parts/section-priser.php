<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$priser_label     = lo_get_option( 'lo_priser_label', 'Priser' );
$priser_title     = lo_get_option( 'lo_priser_title', 'Våre priser' );
$priser_badge     = lo_get_option( 'lo_priser_badge', 'Vanligst' );
$priser_helfo     = lo_get_option( 'lo_priser_helfo_note', '' );
$priser_cancel    = lo_get_option( 'lo_priser_cancel_note', '' );

// Price cards: skip if title is empty
$price_cards = array();
for ( $i = 1; $i <= 3; $i++ ) {
    $title = lo_get_option( "lo_price{$i}_title", '' );
    if ( ! empty( trim( $title ) ) ) {
        $price_cards[] = array(
            'title'    => $title,
            'desc'     => lo_get_option( "lo_price{$i}_desc", '' ),
            'amount'   => lo_get_option( "lo_price{$i}_amount", '' ),
            'featured' => ( $i === 2 ),
        );
    }
}
?>

<?php if ( ! empty( $price_cards ) ) : ?>
<section class="section section-accent" id="priser">
    <div class="container">
        <div class="section-header">
            <?php if ( ! empty( trim( $priser_label ) ) ) : ?>
                <p class="section-label"><?php echo esc_html( $priser_label ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $priser_title ) ) ) : ?>
                <h2 class="section-title"><?php echo esc_html( $priser_title ); ?></h2>
            <?php endif; ?>
        </div>
        <div class="pricing-grid">
            <?php foreach ( $price_cards as $card ) : ?>
                <div class="price-card<?php echo $card['featured'] ? ' featured' : ''; ?>">
                    <?php if ( $card['featured'] && ! empty( trim( $priser_badge ) ) ) : ?>
                        <div class="price-badge"><?php echo esc_html( $priser_badge ); ?></div>
                    <?php endif; ?>
                    <h4><?php echo esc_html( $card['title'] ); ?></h4>
                    <?php if ( ! empty( trim( $card['desc'] ) ) ) : ?>
                        <p class="price-description"><?php echo esc_html( $card['desc'] ); ?></p>
                    <?php endif; ?>
                    <?php if ( ! empty( trim( $card['amount'] ) ) ) : ?>
                        <p class="price-amount"><span class="price-placeholder"><?php echo esc_html( $card['amount'] ); ?></span></p>
                    <?php endif; ?>
                </div>
            <?php endforeach; ?>
        </div>
        <?php if ( ! empty( trim( $priser_helfo ) ) ) : ?>
            <p class="pricing-note"><?php echo esc_html( $priser_helfo ); ?></p>
        <?php endif; ?>
        <?php if ( ! empty( trim( $priser_cancel ) ) ) : ?>
            <p class="pricing-note pricing-note-cancel">
                <i class="fas fa-exclamation-circle"></i>
                <strong>Avbestilling:</strong> <?php echo esc_html( $priser_cancel ); ?>
            </p>
        <?php endif; ?>
    </div>
</section>
<?php endif; ?>
