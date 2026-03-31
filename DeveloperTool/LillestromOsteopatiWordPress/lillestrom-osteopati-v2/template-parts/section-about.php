<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$about_label = lo_get_option( 'lo_about_label', 'Om oss' );
$about_title = lo_get_option( 'lo_about_title', 'Din helse i trygge hender' );
$about_lead  = lo_get_option( 'lo_about_lead', '' );
$about_text1 = lo_get_option( 'lo_about_text1', '' );
$about_text2 = lo_get_option( 'lo_about_text2', '' );

// Stats: only render if both number AND label are non-empty
$about_stats = array();
for ( $i = 1; $i <= 3; $i++ ) {
    $number = lo_get_option( "lo_about_stat{$i}_number", '' );
    $label  = lo_get_option( "lo_about_stat{$i}_label", '' );
    if ( ! empty( trim( $number ) ) && ! empty( trim( $label ) ) ) {
        $about_stats[] = array( 'number' => $number, 'label' => $label );
    }
}
?>

<section class="section section-light" id="om-oss">
    <div class="container">
        <div class="section-header">
            <?php if ( ! empty( trim( $about_label ) ) ) : ?>
                <p class="section-label"><?php echo esc_html( $about_label ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $about_title ) ) ) : ?>
                <h2 class="section-title"><?php echo esc_html( $about_title ); ?></h2>
            <?php endif; ?>
        </div>
        <div class="about-grid">
            <div class="about-image">
                <img src="<?php echo esc_url( get_template_directory_uri() . '/assets/images/klinikk.png' ); ?>" alt="<?php echo esc_attr( $about_label ); ?>" class="about-image-real">
            </div>
            <div class="about-content">
                <?php if ( ! empty( trim( $about_lead ) ) ) : ?>
                    <p class="about-lead"><?php echo wp_kses_post( $about_lead ); ?></p>
                <?php endif; ?>
                <?php if ( ! empty( trim( $about_text1 ) ) ) : ?>
                    <p><?php echo wp_kses_post( $about_text1 ); ?></p>
                <?php endif; ?>
                <?php if ( ! empty( trim( $about_text2 ) ) ) : ?>
                    <p><?php echo wp_kses_post( $about_text2 ); ?></p>
                <?php endif; ?>
                <?php if ( ! empty( $about_stats ) ) : ?>
                    <div class="about-stats">
                        <?php foreach ( $about_stats as $stat ) : ?>
                            <div class="stat">
                                <span class="stat-number"><?php echo esc_html( $stat['number'] ); ?></span>
                                <span class="stat-label"><?php echo esc_html( $stat['label'] ); ?></span>
                            </div>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>
</section>
