<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$osteo_label    = lo_get_option( 'lo_osteo_label', 'Osteopati' );
$osteo_title    = lo_get_option( 'lo_osteo_title', 'Hva er osteopati?' );
$osteo_subtitle = lo_get_option( 'lo_osteo_subtitle', '' );
$osteo_intro1   = lo_get_option( 'lo_osteo_intro1', '' );
$osteo_intro2   = lo_get_option( 'lo_osteo_intro2', '' );
$osteo_who_title = lo_get_option( 'lo_osteo_who_title', '' );
$osteo_who_text1 = lo_get_option( 'lo_osteo_who_text1', '' );
$osteo_who_text2 = lo_get_option( 'lo_osteo_who_text2', '' );

// Cards: only render if title is non-empty
$osteo_cards = array();
for ( $i = 1; $i <= 3; $i++ ) {
    $title = lo_get_option( "lo_osteo_card{$i}_title", '' );
    if ( ! empty( trim( $title ) ) ) {
        $osteo_cards[] = array(
            'icon'  => lo_get_option( "lo_osteo_card{$i}_icon", '' ),
            'title' => $title,
            'text'  => lo_get_option( "lo_osteo_card{$i}_text", '' ),
        );
    }
}
?>

<section class="section section-accent" id="osteopati">
    <div class="container">
        <div class="section-header">
            <?php if ( ! empty( trim( $osteo_label ) ) ) : ?>
                <p class="section-label"><?php echo esc_html( $osteo_label ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $osteo_title ) ) ) : ?>
                <h2 class="section-title"><?php echo esc_html( $osteo_title ); ?></h2>
            <?php endif; ?>
            <?php if ( ! empty( trim( $osteo_subtitle ) ) ) : ?>
                <p class="section-subtitle"><?php echo esc_html( $osteo_subtitle ); ?></p>
            <?php endif; ?>
        </div>
        <?php if ( ! empty( trim( $osteo_intro1 ) ) || ! empty( trim( $osteo_intro2 ) ) ) : ?>
            <div class="osteo-intro">
                <?php if ( ! empty( trim( $osteo_intro1 ) ) ) : ?>
                    <p><?php echo wp_kses_post( $osteo_intro1 ); ?></p>
                <?php endif; ?>
                <?php if ( ! empty( trim( $osteo_intro2 ) ) ) : ?>
                    <p><?php echo wp_kses_post( $osteo_intro2 ); ?></p>
                <?php endif; ?>
            </div>
        <?php endif; ?>
        <?php if ( ! empty( $osteo_cards ) ) : ?>
            <div class="osteo-grid">
                <?php foreach ( $osteo_cards as $card ) : ?>
                    <div class="osteo-card">
                        <?php if ( ! empty( $card['icon'] ) ) : ?>
                            <div class="osteo-card-icon"><i class="fas <?php echo esc_attr( $card['icon'] ); ?>"></i></div>
                        <?php endif; ?>
                        <h3><?php echo esc_html( $card['title'] ); ?></h3>
                        <?php if ( ! empty( trim( $card['text'] ) ) ) : ?>
                            <p><?php echo esc_html( $card['text'] ); ?></p>
                        <?php endif; ?>
                    </div>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>
        <?php if ( ! empty( trim( $osteo_who_title ) ) || ! empty( trim( $osteo_who_text1 ) ) || ! empty( trim( $osteo_who_text2 ) ) ) : ?>
            <div class="osteo-who">
                <?php if ( ! empty( trim( $osteo_who_title ) ) ) : ?>
                    <h3><?php echo esc_html( $osteo_who_title ); ?></h3>
                <?php endif; ?>
                <?php if ( ! empty( trim( $osteo_who_text1 ) ) ) : ?>
                    <p><?php echo wp_kses_post( $osteo_who_text1 ); ?></p>
                <?php endif; ?>
                <?php if ( ! empty( trim( $osteo_who_text2 ) ) ) : ?>
                    <p><?php echo wp_kses_post( $osteo_who_text2 ); ?></p>
                <?php endif; ?>
            </div>
        <?php endif; ?>
    </div>
</section>
