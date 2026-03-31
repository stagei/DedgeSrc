<?php if (!defined('ABSPATH')) exit; ?>

<section class="section section-takk" id="thankyou">
    <div class="container">
        <div class="takk-content">
            <div class="takk-icon"><i class="fas fa-check-circle"></i></div>
            <h2><?php echo esc_html( op_get_option( 'op_thankyou_heading', 'Thank you for your enquiry!' ) ); ?></h2>
            <p><?php echo esc_html( op_get_option( 'op_thankyou_text', 'We have received your message and will respond as soon as possible — usually within one business day.' ) ); ?></p>
            <a href="#home" class="btn btn-primary"><?php echo esc_html( op_get_option( 'op_thankyou_button', 'Back to Home' ) ); ?></a>
        </div>
    </div>
</section>
