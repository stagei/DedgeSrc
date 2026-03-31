<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$pricing_label     = op_get_option( 'op_pricing_label', 'Pricing' );
$pricing_title     = op_get_option( 'op_pricing_title', 'Our Prices' );
$pricing_badge     = op_get_option( 'op_pricing_badge', 'Most Popular' );
$pricing_helfo     = op_get_option( 'op_pricing_helfo_note', '' );
$pricing_cancel    = op_get_option( 'op_pricing_cancel_note', '' );

// Price cards: skip if title is empty
$price_cards = array();
for ( $i = 1; $i <= 3; $i++ ) {
    $title = op_get_option( "op_price{$i}_title", '' );
    if ( ! empty( trim( $title ) ) ) {
        $price_cards[] = array(
            'title'    => $title,
            'desc'     => op_get_option( "op_price{$i}_desc", '' ),
            'amount'   => op_get_option( "op_price{$i}_amount", '' ),
            'featured' => ( $i === 2 ),
        );
    }
}
?>

<?php if ( ! empty( $price_cards ) ) : ?>
<section class="section section-accent" id="pricing">
    <div class="container">
        <div class="section-header">
            <?php if ( ! empty( trim( $pricing_label ) ) ) : ?>
                <p class="section-label"><?php echo esc_html( $pricing_label ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $pricing_title ) ) ) : ?>
                <h2 class="section-title"><?php echo esc_html( $pricing_title ); ?></h2>
            <?php endif; ?>
        </div>
        <div class="pricing-grid">
            <?php foreach ( $price_cards as $card ) : ?>
                <div class="price-card<?php echo $card['featured'] ? ' featured' : ''; ?>">
                    <?php if ( $card['featured'] && ! empty( trim( $pricing_badge ) ) ) : ?>
                        <div class="price-badge"><?php echo esc_html( $pricing_badge ); ?></div>
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
        <?php if ( ! empty( trim( $pricing_helfo ) ) ) : ?>
            <p class="pricing-note"><?php echo esc_html( $pricing_helfo ); ?></p>
        <?php endif; ?>
        <?php if ( ! empty( trim( $pricing_cancel ) ) ) : ?>
            <p class="pricing-note pricing-note-cancel">
                <i class="fas fa-exclamation-circle"></i>
                <strong><?php esc_html_e( 'Cancellation:', 'onepager' ); ?></strong> <?php echo esc_html( $pricing_cancel ); ?>
            </p>
        <?php endif; ?>
    </div>
</section>
<?php endif; ?>
