<?php if (!defined('ABSPATH')) exit; ?>

<?php
$cta_title     = lo_get_option( 'lo_cta_title', '' );
$cta_text      = lo_get_option( 'lo_cta_text', '' );
$cta_phone     = lo_get_option( 'lo_cta_phone', '' );
$cta_email     = lo_get_option( 'lo_contact_email', '' );
$cta_btn_call  = lo_get_option( 'lo_cta_btn_call', 'Ring' );
$cta_btn_email = lo_get_option( 'lo_cta_btn_email', 'Send e-post' );
$cta_trust     = lo_get_option( 'lo_cta_trust_note', '' );
$cta_trust_icon = lo_get_option( 'lo_cta_trust_icon', 'fa-shield-alt' );
$cta_phone_stripped = preg_replace( '/\s+/', '', $cta_phone );
?>

<section class="section section-cta" id="timebestilling">
    <div class="container">
        <div class="cta-content">
            <?php if ( ! empty( trim( $cta_title ) ) ) : ?>
                <h2><?php echo esc_html( $cta_title ); ?></h2>
            <?php endif; ?>
            <?php if ( ! empty( trim( $cta_text ) ) ) : ?>
                <p><?php echo esc_html( $cta_text ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $cta_phone ) ) || ! empty( trim( $cta_email ) ) ) : ?>
                <div class="cta-buttons">
                    <?php if ( ! empty( trim( $cta_phone ) ) ) : ?>
                        <a href="tel:<?php echo esc_attr( $cta_phone_stripped ); ?>" class="btn btn-primary btn-large">
                            <i class="fas fa-phone"></i> <?php echo esc_html( $cta_btn_call ); ?> <?php echo esc_html( $cta_phone ); ?>
                        </a>
                    <?php endif; ?>
                    <?php if ( ! empty( trim( $cta_email ) ) && ! empty( trim( $cta_btn_email ) ) ) : ?>
                        <a href="mailto:<?php echo esc_attr( $cta_email ); ?>" class="btn btn-secondary btn-large">
                            <i class="fas fa-envelope"></i> <?php echo esc_html( $cta_btn_email ); ?>
                        </a>
                    <?php endif; ?>
                </div>
            <?php endif; ?>
            <?php if ( ! empty( trim( $cta_trust ) ) ) : ?>
                <p class="cta-note">
                    <?php if ( ! empty( $cta_trust_icon ) ) : ?>
                        <i class="fas <?php echo esc_attr( $cta_trust_icon ); ?>"></i>
                    <?php endif; ?>
                    <?php echo esc_html( $cta_trust ); ?>
                </p>
            <?php endif; ?>
        </div>
    </div>
</section>
