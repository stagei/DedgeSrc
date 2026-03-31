<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$enterprise_label       = op_get_option( 'op_enterprise_label', 'Enterprise' );
$enterprise_title       = op_get_option( 'op_enterprise_title', 'Services for Businesses' );
$enterprise_subtitle    = op_get_option( 'op_enterprise_subtitle', '' );
$enterprise_description = op_get_option( 'op_enterprise_description', '' );
$enterprise_stat_heading = op_get_option( 'op_enterprise_stat_heading', '' );
$enterprise_stat_icon   = op_get_option( 'op_enterprise_stat_icon', 'fa-exclamation-triangle' );
$enterprise_cta_text    = op_get_option( 'op_enterprise_cta_text', '' );
$enterprise_cta_button  = op_get_option( 'op_enterprise_cta_button', '' );

// Benefits: individual text + icon pairs, skip empty
$benefits = array();
for ( $i = 1; $i <= 6; $i++ ) {
    $text = op_get_option( "op_enterprise_benefit{$i}_text", '' );
    if ( ! empty( trim( $text ) ) ) {
        $benefits[] = array(
            'text' => $text,
            'icon' => op_get_option( "op_enterprise_benefit{$i}_icon", 'fa-check' ),
        );
    }
}

// Service cards: skip if title is empty
$service_cards = array();
for ( $i = 1; $i <= 3; $i++ ) {
    $title = op_get_option( "op_enterprise_card{$i}_title", '' );
    if ( ! empty( trim( $title ) ) ) {
        $service_cards[] = array(
            'icon'  => op_get_option( "op_enterprise_card{$i}_icon", '' ),
            'title' => $title,
            'text'  => op_get_option( "op_enterprise_card{$i}_text", '' ),
        );
    }
}

// Stats: skip empty
$stats = array();
for ( $i = 1; $i <= 3; $i++ ) {
    $stat = op_get_option( "op_enterprise_stat{$i}", '' );
    if ( ! empty( trim( $stat ) ) ) {
        $stats[] = $stat;
    }
}
?>

<section class="section section-dark" id="enterprise">
    <div class="container">
        <div class="section-header">
            <?php if ( ! empty( trim( $enterprise_label ) ) ) : ?>
                <p class="section-label light"><?php echo esc_html( $enterprise_label ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $enterprise_title ) ) ) : ?>
                <h2 class="section-title light"><?php echo esc_html( $enterprise_title ); ?></h2>
            <?php endif; ?>
            <?php if ( ! empty( trim( $enterprise_subtitle ) ) ) : ?>
                <p class="section-subtitle" style="color: rgba(255,255,255,0.75);"><?php echo esc_html( $enterprise_subtitle ); ?></p>
            <?php endif; ?>
        </div>

        <?php if ( ! empty( $benefits ) ) : ?>
            <div class="bedrift-benefits">
                <?php foreach ( $benefits as $benefit ) : ?>
                    <div class="bedrift-benefit">
                        <?php if ( ! empty( $benefit['icon'] ) ) : ?>
                            <i class="fas <?php echo esc_attr( $benefit['icon'] ); ?>"></i>
                        <?php endif; ?>
                        <span><?php echo esc_html( $benefit['text'] ); ?></span>
                    </div>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>

        <?php if ( ! empty( trim( $enterprise_description ) ) ) : ?>
            <div class="bedrift-description">
                <p><?php echo wp_kses_post( $enterprise_description ); ?></p>
            </div>
        <?php endif; ?>

        <?php if ( ! empty( $service_cards ) ) : ?>
            <div class="bedrift-services">
                <?php foreach ( $service_cards as $card ) : ?>
                    <div class="bedrift-card">
                        <?php if ( ! empty( $card['icon'] ) ) : ?>
                            <div class="bedrift-card-icon"><i class="fas <?php echo esc_attr( $card['icon'] ); ?>"></i></div>
                        <?php endif; ?>
                        <h4><?php echo esc_html( $card['title'] ); ?></h4>
                        <?php if ( ! empty( trim( $card['text'] ) ) ) : ?>
                            <p><?php echo esc_html( $card['text'] ); ?></p>
                        <?php endif; ?>
                    </div>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>

        <?php if ( ! empty( $stats ) || ! empty( trim( $enterprise_stat_heading ) ) ) : ?>
            <div class="bedrift-stats">
                <div class="bedrift-stat-box">
                    <?php if ( ! empty( trim( $enterprise_stat_heading ) ) ) : ?>
                        <h4>
                            <?php if ( ! empty( $enterprise_stat_icon ) ) : ?>
                                <i class="fas <?php echo esc_attr( $enterprise_stat_icon ); ?>"></i>
                            <?php endif; ?>
                            <?php echo esc_html( $enterprise_stat_heading ); ?>
                        </h4>
                    <?php endif; ?>
                    <?php if ( ! empty( $stats ) ) : ?>
                        <ul>
                            <?php foreach ( $stats as $stat ) : ?>
                                <li><?php echo esc_html( $stat ); ?></li>
                            <?php endforeach; ?>
                        </ul>
                    <?php endif; ?>
                </div>
            </div>
        <?php endif; ?>

        <?php if ( ! empty( trim( $enterprise_cta_text ) ) || ! empty( trim( $enterprise_cta_button ) ) ) : ?>
            <div class="bedrift-cta">
                <?php if ( ! empty( trim( $enterprise_cta_text ) ) ) : ?>
                    <p><?php echo esc_html( $enterprise_cta_text ); ?></p>
                <?php endif; ?>
                <?php if ( ! empty( trim( $enterprise_cta_button ) ) ) : ?>
                    <a href="#contact" class="btn btn-primary"><i class="fas fa-envelope"></i> <?php echo esc_html( $enterprise_cta_button ); ?></a>
                <?php endif; ?>
            </div>
        <?php endif; ?>
    </div>
</section>
