<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$expertise_label    = op_get_option( 'op_expertise_label', 'Expertise' );
$expertise_title    = op_get_option( 'op_expertise_title', 'What is our expertise?' );
$expertise_subtitle = op_get_option( 'op_expertise_subtitle', '' );
$expertise_intro1   = op_get_option( 'op_expertise_intro1', '' );
$expertise_intro2   = op_get_option( 'op_expertise_intro2', '' );
$expertise_who_title = op_get_option( 'op_expertise_who_title', '' );
$expertise_who_text1 = op_get_option( 'op_expertise_who_text1', '' );
$expertise_who_text2 = op_get_option( 'op_expertise_who_text2', '' );

// Cards: only render if title is non-empty
$expertise_cards = array();
for ( $i = 1; $i <= 3; $i++ ) {
    $title = op_get_option( "op_expertise_card{$i}_title", '' );
    if ( ! empty( trim( $title ) ) ) {
        $expertise_cards[] = array(
            'icon'  => op_get_option( "op_expertise_card{$i}_icon", '' ),
            'title' => $title,
            'text'  => op_get_option( "op_expertise_card{$i}_text", '' ),
        );
    }
}
?>

<section class="section section-accent" id="expertise">
    <div class="container">
        <div class="section-header">
            <?php if ( ! empty( trim( $expertise_label ) ) ) : ?>
                <p class="section-label"><?php echo esc_html( $expertise_label ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $expertise_title ) ) ) : ?>
                <h2 class="section-title"><?php echo esc_html( $expertise_title ); ?></h2>
            <?php endif; ?>
            <?php if ( ! empty( trim( $expertise_subtitle ) ) ) : ?>
                <p class="section-subtitle"><?php echo esc_html( $expertise_subtitle ); ?></p>
            <?php endif; ?>
        </div>
        <?php if ( ! empty( trim( $expertise_intro1 ) ) || ! empty( trim( $expertise_intro2 ) ) ) : ?>
            <div class="osteo-intro">
                <?php if ( ! empty( trim( $expertise_intro1 ) ) ) : ?>
                    <p><?php echo wp_kses_post( $expertise_intro1 ); ?></p>
                <?php endif; ?>
                <?php if ( ! empty( trim( $expertise_intro2 ) ) ) : ?>
                    <p><?php echo wp_kses_post( $expertise_intro2 ); ?></p>
                <?php endif; ?>
            </div>
        <?php endif; ?>
        <?php if ( ! empty( $expertise_cards ) ) : ?>
            <div class="osteo-grid">
                <?php foreach ( $expertise_cards as $card ) : ?>
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
        <?php if ( ! empty( trim( $expertise_who_title ) ) || ! empty( trim( $expertise_who_text1 ) ) || ! empty( trim( $expertise_who_text2 ) ) ) : ?>
            <div class="osteo-who">
                <?php if ( ! empty( trim( $expertise_who_title ) ) ) : ?>
                    <h3><?php echo esc_html( $expertise_who_title ); ?></h3>
                <?php endif; ?>
                <?php if ( ! empty( trim( $expertise_who_text1 ) ) ) : ?>
                    <p><?php echo wp_kses_post( $expertise_who_text1 ); ?></p>
                <?php endif; ?>
                <?php if ( ! empty( trim( $expertise_who_text2 ) ) ) : ?>
                    <p><?php echo wp_kses_post( $expertise_who_text2 ); ?></p>
                <?php endif; ?>
            </div>
        <?php endif; ?>
    </div>
</section>
