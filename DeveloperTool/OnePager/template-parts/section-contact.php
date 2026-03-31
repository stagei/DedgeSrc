<?php if (!defined('ABSPATH')) exit; ?>

<?php
$contact_label   = op_get_option( 'op_contact_label', 'Contact' );
$contact_title   = op_get_option( 'op_contact_title', 'Get In Touch' );
$contact_form_h  = op_get_option( 'op_contact_form_heading', 'Send us a message' );
$address = op_get_option( 'op_contact_address', '' );
$phone   = op_get_option( 'op_contact_phone', '' );
$email   = op_get_option( 'op_contact_email', '' );
$hours   = op_get_option( 'op_contact_hours', '' );
$phone_stripped = preg_replace( '/\s+/', '', $phone );

// Contact items: only render if value is non-empty
$contact_items = array();
if ( ! empty( trim( $address ) ) ) {
    $contact_items[] = array( 'icon' => 'fa-map-marker-alt', 'heading' => __( 'Address', 'onepager' ), 'value' => nl2br( esc_html( $address ) ), 'raw' => true );
}
if ( ! empty( trim( $phone ) ) ) {
    $contact_items[] = array( 'icon' => 'fa-phone', 'heading' => __( 'Phone', 'onepager' ), 'value' => '<a href="tel:' . esc_attr( $phone_stripped ) . '">' . esc_html( $phone ) . '</a>', 'raw' => true );
}
if ( ! empty( trim( $email ) ) ) {
    $contact_items[] = array( 'icon' => 'fa-envelope', 'heading' => __( 'Email', 'onepager' ), 'value' => '<a href="mailto:' . esc_attr( $email ) . '">' . esc_html( $email ) . '</a>', 'raw' => true );
}
if ( ! empty( trim( $hours ) ) ) {
    $contact_items[] = array( 'icon' => 'fa-clock', 'heading' => __( 'Opening Hours', 'onepager' ), 'value' => nl2br( esc_html( $hours ) ), 'raw' => true );
}
?>

<section class="section section-light" id="contact">
    <div class="container">
        <div class="section-header">
            <?php if ( ! empty( trim( $contact_label ) ) ) : ?>
                <p class="section-label"><?php echo esc_html( $contact_label ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $contact_title ) ) ) : ?>
                <h2 class="section-title"><?php echo esc_html( $contact_title ); ?></h2>
            <?php endif; ?>
        </div>
        <div class="contact-grid">
            <?php if ( ! empty( $contact_items ) ) : ?>
                <div class="contact-info">
                    <?php foreach ( $contact_items as $item ) : ?>
                        <div class="contact-item">
                            <div class="contact-icon"><i class="fas <?php echo esc_attr( $item['icon'] ); ?>"></i></div>
                            <div>
                                <h4><?php echo esc_html( $item['heading'] ); ?></h4>
                                <p><?php echo $item['value']; /* Already escaped above */ ?></p>
                            </div>
                        </div>
                    <?php endforeach; ?>
                </div>
            <?php endif; ?>
            <div class="contact-form-wrap">
                <?php if ( ! empty( trim( $contact_form_h ) ) ) : ?>
                    <h3><?php echo esc_html( $contact_form_h ); ?></h3>
                <?php endif; ?>
                <?php
                $cf7_id = get_theme_mod( 'op_cf7_form_id' );
                if ( $cf7_id && shortcode_exists( 'contact-form-7' ) ) {
                    echo do_shortcode( '[contact-form-7 id="' . intval( $cf7_id ) . '" html_class="contact-form"]' );
                } else {
                    $form_email = ! empty( trim( $email ) ) ? $email : get_option( 'admin_email' );
                ?>
                    <form action="https://formsubmit.co/<?php echo esc_attr( $form_email ); ?>" method="POST" class="contact-form">
                        <input type="text" name="_honey" style="display:none">
                        <input type="hidden" name="_captcha" value="false">
                        <input type="hidden" name="_subject" value="<?php esc_attr_e( 'New enquiry from the website', 'onepager' ); ?>">
                        <div class="form-group">
                            <label><?php esc_html_e( 'Name', 'onepager' ); ?> <span class="required">*</span></label>
                            <input type="text" name="name" placeholder="<?php esc_attr_e( 'Your full name', 'onepager' ); ?>" required>
                        </div>
                        <div class="form-group">
                            <label><?php esc_html_e( 'Email', 'onepager' ); ?> <span class="required">*</span></label>
                            <input type="email" name="email" placeholder="<?php esc_attr_e( 'your@email.com', 'onepager' ); ?>" required>
                        </div>
                        <div class="form-group">
                            <label><?php esc_html_e( 'Phone', 'onepager' ); ?></label>
                            <input type="tel" name="phone" placeholder="<?php esc_attr_e( 'Optional', 'onepager' ); ?>">
                        </div>
                        <div class="form-group">
                            <label><?php esc_html_e( 'Message', 'onepager' ); ?> <span class="required">*</span></label>
                            <textarea name="message" rows="5" placeholder="<?php esc_attr_e( 'Briefly describe how we can help you...', 'onepager' ); ?>" required></textarea>
                        </div>
                        <button type="submit" class="btn btn-primary btn-submit">
                            <i class="fas fa-paper-plane"></i> <?php esc_html_e( 'Send Message', 'onepager' ); ?>
                        </button>
                    </form>
                <?php } ?>
            </div>
        </div>
    </div>
</section>
