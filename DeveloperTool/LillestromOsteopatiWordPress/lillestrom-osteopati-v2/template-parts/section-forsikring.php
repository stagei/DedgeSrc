<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$forsikring_label        = lo_get_option( 'lo_forsikring_label', 'Forsikring' );
$forsikring_title        = lo_get_option( 'lo_forsikring_title', 'Behandlingsforsikring' );
$forsikring_subtitle     = lo_get_option( 'lo_forsikring_subtitle', '' );
$forsikring_steps_heading = lo_get_option( 'lo_forsikring_steps_heading', 'Slik bruker du forsikringen din' );
$forsikring_companies_heading = lo_get_option( 'lo_forsikring_companies_heading', 'Vi samarbeider med blant annet' );
$forsikring_note         = lo_get_option( 'lo_forsikring_note', '' );

// Steps: only render if title is non-empty
$forsikring_steps = array();
for ( $i = 1; $i <= 3; $i++ ) {
    $title = lo_get_option( "lo_forsikring_step{$i}_title", '' );
    if ( ! empty( trim( $title ) ) ) {
        $forsikring_steps[] = array(
            'title' => $title,
            'text'  => lo_get_option( "lo_forsikring_step{$i}_text", '' ),
        );
    }
}

// Companies: filter out empty entries
$companies_raw = lo_get_option( 'lo_forsikring_companies', '' );
$companies = array_filter( array_map( 'trim', explode( ',', $companies_raw ) ) );
?>

<section class="section section-light" id="forsikring">
    <div class="container">
        <div class="section-header">
            <?php if ( ! empty( trim( $forsikring_label ) ) ) : ?>
                <p class="section-label"><?php echo esc_html( $forsikring_label ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $forsikring_title ) ) ) : ?>
                <h2 class="section-title"><?php echo esc_html( $forsikring_title ); ?></h2>
            <?php endif; ?>
            <?php if ( ! empty( trim( $forsikring_subtitle ) ) ) : ?>
                <p class="section-subtitle"><?php echo esc_html( $forsikring_subtitle ); ?></p>
            <?php endif; ?>
        </div>
        <div class="insurance-content">
            <?php if ( ! empty( $forsikring_steps ) ) : ?>
                <div class="insurance-steps">
                    <?php if ( ! empty( trim( $forsikring_steps_heading ) ) ) : ?>
                        <h3><?php echo esc_html( $forsikring_steps_heading ); ?></h3>
                    <?php endif; ?>
                    <ol class="insurance-list">
                        <?php foreach ( $forsikring_steps as $step ) : ?>
                            <li>
                                <strong><?php echo esc_html( $step['title'] ); ?></strong>
                                <?php if ( ! empty( trim( $step['text'] ) ) ) : ?>
                                    <span><?php echo esc_html( $step['text'] ); ?></span>
                                <?php endif; ?>
                            </li>
                        <?php endforeach; ?>
                    </ol>
                </div>
            <?php endif; ?>
            <?php if ( ! empty( $companies ) ) : ?>
                <div class="insurance-companies">
                    <?php if ( ! empty( trim( $forsikring_companies_heading ) ) ) : ?>
                        <h3><?php echo esc_html( $forsikring_companies_heading ); ?></h3>
                    <?php endif; ?>
                    <div class="insurance-logos">
                        <?php foreach ( $companies as $company ) : ?>
                            <div class="insurance-logo-item"><?php echo esc_html( $company ); ?></div>
                        <?php endforeach; ?>
                    </div>
                    <?php if ( ! empty( trim( $forsikring_note ) ) ) : ?>
                        <p class="insurance-note">
                            <i class="fas fa-info-circle"></i>
                            <?php echo esc_html( $forsikring_note ); ?>
                        </p>
                    <?php endif; ?>
                </div>
            <?php endif; ?>
        </div>
    </div>
</section>
