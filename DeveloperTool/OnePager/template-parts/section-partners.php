<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$partners_label        = op_get_option( 'op_partners_label', 'Partners' );
$partners_title        = op_get_option( 'op_partners_title', 'Our Partners' );
$partners_subtitle     = op_get_option( 'op_partners_subtitle', '' );
$partners_steps_heading = op_get_option( 'op_partners_steps_heading', 'How it works' );
$partners_companies_heading = op_get_option( 'op_partners_companies_heading', 'We collaborate with' );
$partners_note         = op_get_option( 'op_partners_note', '' );

// Steps: only render if title is non-empty
$partners_steps = array();
for ( $i = 1; $i <= 3; $i++ ) {
    $title = op_get_option( "op_partners_step{$i}_title", '' );
    if ( ! empty( trim( $title ) ) ) {
        $partners_steps[] = array(
            'title' => $title,
            'text'  => op_get_option( "op_partners_step{$i}_text", '' ),
        );
    }
}

// Companies: filter out empty entries
$companies_raw = op_get_option( 'op_partners_companies', '' );
$companies = array_filter( array_map( 'trim', explode( ',', $companies_raw ) ) );
?>

<section class="section section-light" id="partners">
    <div class="container">
        <div class="section-header">
            <?php if ( ! empty( trim( $partners_label ) ) ) : ?>
                <p class="section-label"><?php echo esc_html( $partners_label ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $partners_title ) ) ) : ?>
                <h2 class="section-title"><?php echo esc_html( $partners_title ); ?></h2>
            <?php endif; ?>
            <?php if ( ! empty( trim( $partners_subtitle ) ) ) : ?>
                <p class="section-subtitle"><?php echo esc_html( $partners_subtitle ); ?></p>
            <?php endif; ?>
        </div>
        <div class="insurance-content">
            <?php if ( ! empty( $partners_steps ) ) : ?>
                <div class="insurance-steps">
                    <?php if ( ! empty( trim( $partners_steps_heading ) ) ) : ?>
                        <h3><?php echo esc_html( $partners_steps_heading ); ?></h3>
                    <?php endif; ?>
                    <ol class="insurance-list">
                        <?php foreach ( $partners_steps as $step ) : ?>
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
                    <?php if ( ! empty( trim( $partners_companies_heading ) ) ) : ?>
                        <h3><?php echo esc_html( $partners_companies_heading ); ?></h3>
                    <?php endif; ?>
                    <div class="insurance-logos">
                        <?php foreach ( $companies as $company ) : ?>
                            <div class="insurance-logo-item"><?php echo esc_html( $company ); ?></div>
                        <?php endforeach; ?>
                    </div>
                    <?php if ( ! empty( trim( $partners_note ) ) ) : ?>
                        <p class="insurance-note">
                            <i class="fas fa-info-circle"></i>
                            <?php echo esc_html( $partners_note ); ?>
                        </p>
                    <?php endif; ?>
                </div>
            <?php endif; ?>
        </div>
    </div>
</section>
