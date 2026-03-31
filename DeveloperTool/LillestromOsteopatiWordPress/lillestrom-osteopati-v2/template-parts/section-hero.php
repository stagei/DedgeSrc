<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$hero_subtitle     = lo_get_option( 'lo_hero_subtitle', 'Velkommen til' );
$hero_title        = lo_get_option( 'lo_hero_title', 'Lillestrøm Osteopati' );
$hero_description  = lo_get_option( 'lo_hero_description', '' );
$hero_btn_primary  = lo_get_option( 'lo_hero_btn_primary', 'Bestill time' );
$hero_btn_secondary = lo_get_option( 'lo_hero_btn_secondary', 'Les mer om osteopati' );

// Badges: each is an array of [text, icon] — rendered only if text is non-empty
$hero_badges = array();
for ( $i = 1; $i <= 3; $i++ ) {
    $text = lo_get_option( "lo_hero_badge{$i}", '' );
    $icon = lo_get_option( "lo_hero_badge{$i}_icon", '' );
    if ( ! empty( trim( $text ) ) ) {
        $hero_badges[] = array( 'text' => $text, 'icon' => $icon );
    }
}
?>

<section class="hero" id="hjem">
    <div class="hero-overlay"></div>
    <div class="container hero-content">
        <?php if ( ! empty( trim( $hero_subtitle ) ) ) : ?>
            <p class="hero-subtitle"><?php echo esc_html( $hero_subtitle ); ?></p>
        <?php endif; ?>
        <?php if ( ! empty( trim( $hero_title ) ) ) : ?>
            <h1 class="hero-title"><?php echo esc_html( $hero_title ); ?></h1>
        <?php endif; ?>
        <?php if ( ! empty( trim( $hero_description ) ) ) : ?>
            <p class="hero-description"><?php echo esc_html( $hero_description ); ?></p>
        <?php endif; ?>
        <?php if ( ! empty( trim( $hero_btn_primary ) ) || ! empty( trim( $hero_btn_secondary ) ) ) : ?>
            <div class="hero-buttons">
                <?php if ( ! empty( trim( $hero_btn_primary ) ) ) : ?>
                    <a href="#timebestilling" class="btn btn-primary"><?php echo esc_html( $hero_btn_primary ); ?></a>
                <?php endif; ?>
                <?php if ( ! empty( trim( $hero_btn_secondary ) ) ) : ?>
                    <a href="#osteopati" class="btn btn-secondary"><?php echo esc_html( $hero_btn_secondary ); ?></a>
                <?php endif; ?>
            </div>
        <?php endif; ?>
        <?php if ( ! empty( $hero_badges ) ) : ?>
            <div class="hero-badges">
                <?php foreach ( $hero_badges as $badge ) : ?>
                    <div class="badge">
                        <?php if ( ! empty( $badge['icon'] ) ) : ?>
                            <i class="fas <?php echo esc_attr( $badge['icon'] ); ?>"></i>
                        <?php endif; ?>
                        <span><?php echo esc_html( $badge['text'] ); ?></span>
                    </div>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>
    </div>
    <div class="hero-scroll">
        <a href="#om-oss"><i class="fas fa-chevron-down"></i></a>
    </div>
</section>
