<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$footer_tagline    = op_get_option( 'op_footer_tagline', 'Professional services in the heart of your city. Trusted experts since 2020.' );
$contact_address   = op_get_option( 'op_contact_address', "123 Business Street\nCity, Country" );
$contact_email     = op_get_option( 'op_contact_email', 'hello@example.com' );
$footer_copyright  = op_get_option( 'op_footer_copyright', 'Your Company. All rights reserved.' );
$footer_membership = op_get_option( 'op_footer_membership', '' );
$footer_member_url = op_get_option( 'op_footer_membership_url', '' );

$address_lines      = explode( "\n", $contact_address );
$address_first_line = trim( $address_lines[0] );
?>

    <footer class="footer">
        <div class="container">
            <div class="footer-grid">
                <div class="footer-brand">
                    <div class="footer-logo">
                        <?php if ( has_custom_logo() ) : ?>
                            <?php
                            $custom_logo_id = get_theme_mod( 'custom_logo' );
                            $logo_url = wp_get_attachment_image_url( $custom_logo_id, 'full' );
                            ?>
                            <img src="<?php echo esc_url( $logo_url ); ?>" alt="<?php echo esc_attr( get_bloginfo( 'name' ) ); ?>" class="footer-logo-icon">
                        <?php else : ?>
                            <img src="<?php echo esc_url( get_template_directory_uri() ); ?>/assets/images/logo.png" alt="<?php echo esc_attr( get_bloginfo( 'name' ) ); ?>" class="footer-logo-icon">
                        <?php endif; ?>
                        <span class="logo-text"><strong><?php echo esc_html( get_bloginfo( 'name' ) ); ?></strong></span>
                    </div>
                    <p><?php echo esc_html( $footer_tagline ); ?></p>
                </div>
                <div class="footer-links">
                    <h4><?php esc_html_e( 'Pages', 'onepager' ); ?></h4>
                    <ul>
                        <li><a href="#home"><?php esc_html_e( 'Home', 'onepager' ); ?></a></li>
                        <li><a href="#about"><?php esc_html_e( 'About', 'onepager' ); ?></a></li>
                        <li><a href="#expertise"><?php esc_html_e( 'Expertise', 'onepager' ); ?></a></li>
                        <li><a href="#services"><?php esc_html_e( 'Services', 'onepager' ); ?></a></li>
                        <li><a href="#partners"><?php esc_html_e( 'Partners', 'onepager' ); ?></a></li>
                        <li><a href="#enterprise"><?php esc_html_e( 'Enterprise', 'onepager' ); ?></a></li>
                    </ul>
                </div>
                <div class="footer-links">
                    <h4><?php esc_html_e( 'Practical Info', 'onepager' ); ?></h4>
                    <ul>
                        <li><a href="#pricing"><?php esc_html_e( 'Pricing', 'onepager' ); ?></a></li>
                        <li><a href="#contact"><?php esc_html_e( 'Contact', 'onepager' ); ?></a></li>
                        <li><a href="#cta"><?php esc_html_e( 'Get Started', 'onepager' ); ?></a></li>
                    </ul>
                </div>
                <div class="footer-contact">
                    <h4><?php esc_html_e( 'Contact Us', 'onepager' ); ?></h4>
                    <p><?php echo esc_html( $address_first_line ); ?></p>
                    <p><a href="mailto:<?php echo esc_attr( $contact_email ); ?>"><?php echo esc_html( $contact_email ); ?></a></p>
                </div>
            </div>
            <div class="footer-bottom">
                <p>&copy; <?php echo esc_html( date( 'Y' ) ); ?> <?php echo esc_html( $footer_copyright ); ?></p>
                <?php if ( ! empty( trim( $footer_membership ) ) ) : ?>
                    <p><?php esc_html_e( 'Member of', 'onepager' ); ?> <a href="<?php echo esc_url( $footer_member_url ); ?>" target="_blank" rel="noopener"><?php echo esc_html( $footer_membership ); ?></a></p>
                <?php endif; ?>
            </div>
        </div>
    </footer>

    <?php wp_footer(); ?>
</body>
</html>
