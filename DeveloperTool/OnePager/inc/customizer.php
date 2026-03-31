<?php
/**
 * OnePager Theme Customizer
 *
 * @package OnePager
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

function op_customize_register( $wp_customize ) {

    $wp_customize->add_panel( 'op_panel', array(
        'title'    => __( 'OnePager Content', 'onepager' ),
        'priority' => 30,
    ) );

    // =========================================================================
    // Section 1: Hero
    // =========================================================================
    $wp_customize->add_section( 'op_hero', array(
        'title' => __( 'Hero', 'onepager' ),
        'panel' => 'op_panel',
    ) );

    $wp_customize->add_setting( 'op_hero_badge1', array( 'default' => 'Certified Professionals', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_hero_badge1', array( 'label' => __( 'Badge 1 — Text', 'onepager' ), 'section' => 'op_hero', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_hero_badge1_icon', array( 'default' => 'fa-certificate', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_hero_badge1_icon', array( 'label' => __( 'Badge 1 — Icon', 'onepager' ), 'section' => 'op_hero', 'type' => 'select', 'choices' => op_get_icon_choices() ) );

    $wp_customize->add_setting( 'op_hero_badge2', array( 'default' => 'No Waiting Time', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_hero_badge2', array( 'label' => __( 'Badge 2 — Text', 'onepager' ), 'section' => 'op_hero', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_hero_badge2_icon', array( 'default' => 'fa-clock', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_hero_badge2_icon', array( 'label' => __( 'Badge 2 — Icon', 'onepager' ), 'section' => 'op_hero', 'type' => 'select', 'choices' => op_get_icon_choices() ) );

    $wp_customize->add_setting( 'op_hero_badge3', array( 'default' => 'No Referral Needed', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_hero_badge3', array( 'label' => __( 'Badge 3 — Text', 'onepager' ), 'section' => 'op_hero', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_hero_badge3_icon', array( 'default' => 'fa-check-circle', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_hero_badge3_icon', array( 'label' => __( 'Badge 3 — Icon', 'onepager' ), 'section' => 'op_hero', 'type' => 'select', 'choices' => op_get_icon_choices() ) );

    $wp_customize->add_setting( 'op_hero_subtitle', array( 'default' => 'Welcome to', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_hero_subtitle', array( 'label' => __( 'Subtitle', 'onepager' ), 'section' => 'op_hero', 'type' => 'text' ) );

    $wp_customize->add_setting( 'op_hero_title', array( 'default' => 'Your Business Name', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_hero_title', array( 'label' => __( 'Title', 'onepager' ), 'section' => 'op_hero', 'type' => 'text' ) );

    $wp_customize->add_setting( 'op_hero_description', array( 'default' => 'Professional services tailored to your needs. We help you achieve your goals with expertise, dedication, and a personal touch.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_hero_description', array( 'label' => __( 'Description', 'onepager' ), 'section' => 'op_hero', 'type' => 'textarea' ) );

    $wp_customize->add_setting( 'op_hero_btn_primary', array( 'default' => 'Get Started', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_hero_btn_primary', array( 'label' => __( 'Primary Button Text', 'onepager' ), 'section' => 'op_hero', 'type' => 'text' ) );

    $wp_customize->add_setting( 'op_hero_btn_secondary', array( 'default' => 'Learn More', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_hero_btn_secondary', array( 'label' => __( 'Secondary Button Text', 'onepager' ), 'section' => 'op_hero', 'type' => 'text' ) );

    // =========================================================================
    // Section 2: About
    // =========================================================================
    $wp_customize->add_section( 'op_about', array(
        'title' => __( 'About', 'onepager' ),
        'panel' => 'op_panel',
    ) );

    $wp_customize->add_setting( 'op_about_label', array( 'default' => 'About Us', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_about_label', array( 'label' => __( 'Section Label', 'onepager' ), 'section' => 'op_about', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'op_about_title', array( 'default' => 'Your Health in Safe Hands', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_about_title', array( 'label' => __( 'Section Title', 'onepager' ), 'section' => 'op_about', 'type' => 'text', 'priority' => 2 ) );

    $wp_customize->add_setting( 'op_about_lead', array( 'default' => 'We offer comprehensive professional services for you and your family. Our certified team combines thorough assessment with personalized solutions tailored to your needs.', 'sanitize_callback' => 'wp_kses_post' ) );
    $wp_customize->add_control( 'op_about_lead', array( 'label' => __( 'Lead Text', 'onepager' ), 'section' => 'op_about', 'type' => 'textarea' ) );

    $wp_customize->add_setting( 'op_about_text1', array( 'default' => 'Our team has been certified and accredited since 2020, meeting the highest industry standards. No referral needed — contact us directly for an appointment.', 'sanitize_callback' => 'wp_kses_post' ) );
    $wp_customize->add_control( 'op_about_text1', array( 'label' => __( 'Paragraph 1', 'onepager' ), 'section' => 'op_about', 'type' => 'textarea' ) );

    $wp_customize->add_setting( 'op_about_text2', array( 'default' => 'We have a skilled team with broad capacity and can offer appointments on short notice. We take time for each client, focusing on finding the root causes — not just the symptoms.', 'sanitize_callback' => 'wp_kses_post' ) );
    $wp_customize->add_control( 'op_about_text2', array( 'label' => __( 'Paragraph 2', 'onepager' ), 'section' => 'op_about', 'type' => 'textarea' ) );

    $wp_customize->add_setting( 'op_about_stat1_number', array( 'default' => '10+', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_about_stat1_number', array( 'label' => __( 'Stat 1 — Number', 'onepager' ), 'section' => 'op_about', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_about_stat1_label', array( 'default' => 'Years Experience', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_about_stat1_label', array( 'label' => __( 'Stat 1 — Label', 'onepager' ), 'section' => 'op_about', 'type' => 'text' ) );

    $wp_customize->add_setting( 'op_about_stat2_number', array( 'default' => '500+', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_about_stat2_number', array( 'label' => __( 'Stat 2 — Number', 'onepager' ), 'section' => 'op_about', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_about_stat2_label', array( 'default' => 'Happy Clients', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_about_stat2_label', array( 'label' => __( 'Stat 2 — Label', 'onepager' ), 'section' => 'op_about', 'type' => 'text' ) );

    $wp_customize->add_setting( 'op_about_stat3_number', array( 'default' => '100%', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_about_stat3_number', array( 'label' => __( 'Stat 3 — Number', 'onepager' ), 'section' => 'op_about', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_about_stat3_label', array( 'default' => 'Client Focus', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_about_stat3_label', array( 'label' => __( 'Stat 3 — Label', 'onepager' ), 'section' => 'op_about', 'type' => 'text' ) );

    // =========================================================================
    // Section 3: Expertise (was Osteopati)
    // =========================================================================
    $wp_customize->add_section( 'op_expertise', array(
        'title' => __( 'Expertise', 'onepager' ),
        'panel' => 'op_panel',
    ) );

    $wp_customize->add_setting( 'op_expertise_label', array( 'default' => 'Our Expertise', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_label', array( 'label' => __( 'Section Label', 'onepager' ), 'section' => 'op_expertise', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'op_expertise_title', array( 'default' => 'What We Do', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_title', array( 'label' => __( 'Section Title', 'onepager' ), 'section' => 'op_expertise', 'type' => 'text', 'priority' => 2 ) );

    $wp_customize->add_setting( 'op_expertise_subtitle', array( 'default' => 'We are certified professionals with deep knowledge of how various factors connect and impact your success.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_subtitle', array( 'label' => __( 'Subtitle', 'onepager' ), 'section' => 'op_expertise', 'type' => 'textarea' ) );

    $wp_customize->add_setting( 'op_expertise_intro1', array( 'default' => 'Our approach sets us apart from others by seeing the <strong>big picture</strong>. We find the <strong>root cause</strong> — not just treat the symptoms. This is achieved through thorough assessment and solutions aimed at identifying and resolving the underlying issues.', 'sanitize_callback' => 'wp_kses_post' ) );
    $wp_customize->add_control( 'op_expertise_intro1', array( 'label' => __( 'Intro — Paragraph 1', 'onepager' ), 'section' => 'op_expertise', 'type' => 'textarea' ) );

    $wp_customize->add_setting( 'op_expertise_intro2', array( 'default' => 'We tailor our solutions to your needs. We combine expert techniques with guidance and support — whether the goal is to resolve urgent issues or help you manage long-term challenges.', 'sanitize_callback' => 'wp_kses_post' ) );
    $wp_customize->add_control( 'op_expertise_intro2', array( 'label' => __( 'Intro — Paragraph 2', 'onepager' ), 'section' => 'op_expertise', 'type' => 'textarea' ) );

    // Expertise — Card 1
    $wp_customize->add_setting( 'op_expertise_card1_icon', array( 'default' => 'fa-lightbulb', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_card1_icon', array( 'label' => __( 'Card 1 — Icon', 'onepager' ), 'section' => 'op_expertise', 'type' => 'select', 'choices' => op_get_icon_choices() ) );
    $wp_customize->add_setting( 'op_expertise_card1_title', array( 'default' => 'Strategy & Planning', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_card1_title', array( 'label' => __( 'Card 1 — Title', 'onepager' ), 'section' => 'op_expertise', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_expertise_card1_text', array( 'default' => 'Comprehensive strategic planning and analysis to identify opportunities and optimize your approach for maximum impact.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_card1_text', array( 'label' => __( 'Card 1 — Text', 'onepager' ), 'section' => 'op_expertise', 'type' => 'textarea' ) );

    // Expertise — Card 2
    $wp_customize->add_setting( 'op_expertise_card2_icon', array( 'default' => 'fa-cogs', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_card2_icon', array( 'label' => __( 'Card 2 — Icon', 'onepager' ), 'section' => 'op_expertise', 'type' => 'select', 'choices' => op_get_icon_choices() ) );
    $wp_customize->add_setting( 'op_expertise_card2_title', array( 'default' => 'Implementation', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_card2_title', array( 'label' => __( 'Card 2 — Title', 'onepager' ), 'section' => 'op_expertise', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_expertise_card2_text', array( 'default' => 'Expert implementation of solutions designed to deliver measurable results and improve your operations efficiently.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_card2_text', array( 'label' => __( 'Card 2 — Text', 'onepager' ), 'section' => 'op_expertise', 'type' => 'textarea' ) );

    // Expertise — Card 3
    $wp_customize->add_setting( 'op_expertise_card3_icon', array( 'default' => 'fa-chart-line', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_card3_icon', array( 'label' => __( 'Card 3 — Icon', 'onepager' ), 'section' => 'op_expertise', 'type' => 'select', 'choices' => op_get_icon_choices() ) );
    $wp_customize->add_setting( 'op_expertise_card3_title', array( 'default' => 'Growth & Optimization', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_card3_title', array( 'label' => __( 'Card 3 — Title', 'onepager' ), 'section' => 'op_expertise', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_expertise_card3_text', array( 'default' => 'Ongoing optimization and growth strategies to ensure sustainable success and continuous improvement.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_card3_text', array( 'label' => __( 'Card 3 — Text', 'onepager' ), 'section' => 'op_expertise', 'type' => 'textarea' ) );

    // Expertise — Who section
    $wp_customize->add_setting( 'op_expertise_who_title', array( 'default' => 'Who is this for?', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_expertise_who_title', array( 'label' => __( 'Who section — Title', 'onepager' ), 'section' => 'op_expertise', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_expertise_who_text1', array( 'default' => 'Our services are perfect for businesses and individuals seeking a comprehensive, personalized approach. We work with clients of all sizes — from startups to established enterprises.', 'sanitize_callback' => 'wp_kses_post' ) );
    $wp_customize->add_control( 'op_expertise_who_text1', array( 'label' => __( 'Who section — Paragraph 1', 'onepager' ), 'section' => 'op_expertise', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_expertise_who_text2', array( 'default' => 'We handle a broad spectrum of challenges — from urgent issues and operational bottlenecks to long-term strategic goals. Our solutions both address immediate needs and help prevent future problems.', 'sanitize_callback' => 'wp_kses_post' ) );
    $wp_customize->add_control( 'op_expertise_who_text2', array( 'label' => __( 'Who section — Paragraph 2', 'onepager' ), 'section' => 'op_expertise', 'type' => 'textarea' ) );

    // =========================================================================
    // Section 4: Services (CPT-based, just subtitle)
    // =========================================================================
    $wp_customize->add_section( 'op_services', array(
        'title' => __( 'Services', 'onepager' ),
        'panel' => 'op_panel',
    ) );

    $wp_customize->add_setting( 'op_services_label', array( 'default' => 'Services', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_services_label', array( 'label' => __( 'Section Label', 'onepager' ), 'section' => 'op_services', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'op_services_title', array( 'default' => 'How Can We Help You?', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_services_title', array( 'label' => __( 'Section Title', 'onepager' ), 'section' => 'op_services', 'type' => 'text', 'priority' => 2 ) );
    $wp_customize->add_setting( 'op_services_subtitle', array( 'default' => 'We offer a wide range of professional services. Here are some of the most common areas we cover.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_services_subtitle', array( 'label' => __( 'Subtitle', 'onepager' ), 'section' => 'op_services', 'type' => 'textarea' ) );

    // Team headings (under Services section in Customizer)
    $wp_customize->add_setting( 'op_team_label', array( 'default' => 'Our Team', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_team_label', array( 'label' => __( 'Team — Section Label', 'onepager' ), 'section' => 'op_services', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_team_title', array( 'default' => 'Meet Our Experts', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_team_title', array( 'label' => __( 'Team — Section Title', 'onepager' ), 'section' => 'op_services', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_team_credentials_heading', array( 'default' => 'Credentials', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_team_credentials_heading', array( 'label' => __( 'Team — Credentials Heading', 'onepager' ), 'section' => 'op_services', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_team_specialties_heading', array( 'default' => 'Areas of Expertise', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_team_specialties_heading', array( 'label' => __( 'Team — Specialties Heading', 'onepager' ), 'section' => 'op_services', 'type' => 'text' ) );

    // =========================================================================
    // Section 5: Process
    // =========================================================================
    $wp_customize->add_section( 'op_process', array(
        'title' => __( 'Process', 'onepager' ),
        'panel' => 'op_panel',
    ) );

    $wp_customize->add_setting( 'op_process_label', array( 'default' => 'How It Works', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_process_label', array( 'label' => __( 'Section Label', 'onepager' ), 'section' => 'op_process', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'op_process_title', array( 'default' => 'Your First Consultation', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_process_title', array( 'label' => __( 'Section Title', 'onepager' ), 'section' => 'op_process', 'type' => 'text', 'priority' => 2 ) );

    // Steps 1-4
    $steps = array(
        1 => array( 'Discovery', 'We start with a thorough conversation about your needs, background, and goals.' ),
        2 => array( 'Assessment', 'A detailed assessment to map out the current situation and identify key areas.' ),
        3 => array( 'Solution', 'Tailored solutions designed specifically for your unique situation and objectives.' ),
        4 => array( 'Follow-up', 'Ongoing support and a clear plan for continued improvement and success.' ),
    );
    foreach ( $steps as $i => $s ) {
        $wp_customize->add_setting( "op_process_step{$i}_title", array( 'default' => $s[0], 'sanitize_callback' => 'sanitize_text_field' ) );
        $wp_customize->add_control( "op_process_step{$i}_title", array( 'label' => sprintf( __( 'Step %d — Title', 'onepager' ), $i ), 'section' => 'op_process', 'type' => 'text' ) );
        $wp_customize->add_setting( "op_process_step{$i}_text", array( 'default' => $s[1], 'sanitize_callback' => 'sanitize_text_field' ) );
        $wp_customize->add_control( "op_process_step{$i}_text", array( 'label' => sprintf( __( 'Step %d — Text', 'onepager' ), $i ), 'section' => 'op_process', 'type' => 'textarea' ) );
    }

    // =========================================================================
    // Section 6: Partners (was Forsikring)
    // =========================================================================
    $wp_customize->add_section( 'op_partners', array(
        'title' => __( 'Partners', 'onepager' ),
        'panel' => 'op_panel',
    ) );

    $wp_customize->add_setting( 'op_partners_label', array( 'default' => 'Partners', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_label', array( 'label' => __( 'Section Label', 'onepager' ), 'section' => 'op_partners', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'op_partners_title', array( 'default' => 'Our Partners', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_title', array( 'label' => __( 'Section Title', 'onepager' ), 'section' => 'op_partners', 'type' => 'text', 'priority' => 2 ) );

    $wp_customize->add_setting( 'op_partners_subtitle', array( 'default' => 'We work with leading companies and organizations. Our partnerships ensure you receive the best possible service and support.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_subtitle', array( 'label' => __( 'Subtitle', 'onepager' ), 'section' => 'op_partners', 'type' => 'textarea' ) );

    $wp_customize->add_setting( 'op_partners_companies', array( 'default' => 'Partner A, Partner B, Partner C, Partner D, Partner E, Partner F', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_companies', array( 'label' => __( 'Partner Names', 'onepager' ), 'description' => __( 'Comma-separated list of partner names.', 'onepager' ), 'section' => 'op_partners', 'type' => 'textarea' ) );

    $wp_customize->add_setting( 'op_partners_note', array( 'default' => 'Have a different partner in mind? Contact us — we are happy to help find the right solution for you.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_note', array( 'label' => __( 'Note', 'onepager' ), 'section' => 'op_partners', 'type' => 'textarea' ) );

    // Partners — Steps
    $wp_customize->add_setting( 'op_partners_steps_heading', array( 'default' => 'How It Works', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_steps_heading', array( 'label' => __( 'Steps — Heading', 'onepager' ), 'section' => 'op_partners', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_partners_step1_title', array( 'default' => 'Contact the partner', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_step1_title', array( 'label' => __( 'Step 1 — Title', 'onepager' ), 'section' => 'op_partners', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_partners_step1_text', array( 'default' => 'Reach out to your partner organization and register your case.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_step1_text', array( 'label' => __( 'Step 1 — Text', 'onepager' ), 'section' => 'op_partners', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_partners_step2_title', array( 'default' => 'Book an appointment', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_step2_title', array( 'label' => __( 'Step 2 — Title', 'onepager' ), 'section' => 'op_partners', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_partners_step2_text', array( 'default' => 'Provide your reference number when booking and we handle the rest.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_step2_text', array( 'label' => __( 'Step 2 — Text', 'onepager' ), 'section' => 'op_partners', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_partners_step3_title', array( 'default' => 'Direct billing', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_step3_title', array( 'label' => __( 'Step 3 — Title', 'onepager' ), 'section' => 'op_partners', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_partners_step3_text', array( 'default' => 'In most cases we can invoice the partner directly on your behalf.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_step3_text', array( 'label' => __( 'Step 3 — Text', 'onepager' ), 'section' => 'op_partners', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_partners_companies_heading', array( 'default' => 'We work with', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_partners_companies_heading', array( 'label' => __( 'Companies — Heading', 'onepager' ), 'section' => 'op_partners', 'type' => 'text' ) );

    // =========================================================================
    // Section 7: Pricing
    // =========================================================================
    $wp_customize->add_section( 'op_pricing', array(
        'title' => __( 'Pricing', 'onepager' ),
        'panel' => 'op_panel',
    ) );

    $wp_customize->add_setting( 'op_pricing_label', array( 'default' => 'Pricing', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_pricing_label', array( 'label' => __( 'Section Label', 'onepager' ), 'section' => 'op_pricing', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'op_pricing_title', array( 'default' => 'Our Pricing', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_pricing_title', array( 'label' => __( 'Section Title', 'onepager' ), 'section' => 'op_pricing', 'type' => 'text', 'priority' => 2 ) );

    // Price cards 1-3
    $prices = array(
        1 => array( 'Initial Consultation', 'Includes assessment, analysis, and first session (approx. 60 min)', 'Contact us' ),
        2 => array( 'Follow-up Session', 'Continued service for existing clients (approx. 45 min)', 'Contact us' ),
        3 => array( 'Custom Package', 'Tailored service package for specific needs', 'Contact us' ),
    );
    foreach ( $prices as $i => $p ) {
        $wp_customize->add_setting( "op_price{$i}_title", array( 'default' => $p[0], 'sanitize_callback' => 'sanitize_text_field' ) );
        $wp_customize->add_control( "op_price{$i}_title", array( 'label' => sprintf( __( 'Price %d — Title', 'onepager' ), $i ), 'section' => 'op_pricing', 'type' => 'text' ) );
        $wp_customize->add_setting( "op_price{$i}_desc", array( 'default' => $p[1], 'sanitize_callback' => 'sanitize_text_field' ) );
        $wp_customize->add_control( "op_price{$i}_desc", array( 'label' => sprintf( __( 'Price %d — Description', 'onepager' ), $i ), 'section' => 'op_pricing', 'type' => 'textarea' ) );
        $wp_customize->add_setting( "op_price{$i}_amount", array( 'default' => $p[2], 'sanitize_callback' => 'sanitize_text_field' ) );
        $wp_customize->add_control( "op_price{$i}_amount", array( 'label' => sprintf( __( 'Price %d — Amount', 'onepager' ), $i ), 'section' => 'op_pricing', 'type' => 'text' ) );
    }

    $wp_customize->add_setting( 'op_pricing_badge', array( 'default' => 'Most Popular', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_pricing_badge', array( 'label' => __( 'Badge Text (popular price)', 'onepager' ), 'section' => 'op_pricing', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_pricing_note', array( 'default' => 'All prices are exclusive of VAT. Payment is due upon completion of service.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_pricing_note', array( 'label' => __( 'Pricing Note', 'onepager' ), 'section' => 'op_pricing', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_pricing_cancel_note', array( 'default' => 'Please cancel at least 24 hours before your scheduled appointment.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_pricing_cancel_note', array( 'label' => __( 'Cancellation Note', 'onepager' ), 'section' => 'op_pricing', 'type' => 'textarea' ) );

    // =========================================================================
    // Section 8: Contact
    // =========================================================================
    $wp_customize->add_section( 'op_contact', array(
        'title' => __( 'Contact', 'onepager' ),
        'panel' => 'op_panel',
    ) );

    $wp_customize->add_setting( 'op_contact_label', array( 'default' => 'Contact', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_contact_label', array( 'label' => __( 'Section Label', 'onepager' ), 'section' => 'op_contact', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'op_contact_title', array( 'default' => 'Get In Touch', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_contact_title', array( 'label' => __( 'Section Title', 'onepager' ), 'section' => 'op_contact', 'type' => 'text', 'priority' => 2 ) );

    $wp_customize->add_setting( 'op_contact_address', array( 'default' => "123 Business Street\nCity, Country", 'sanitize_callback' => 'wp_kses_post' ) );
    $wp_customize->add_control( 'op_contact_address', array( 'label' => __( 'Address', 'onepager' ), 'section' => 'op_contact', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_contact_phone', array( 'default' => '+1 234 567 890', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_contact_phone', array( 'label' => __( 'Phone', 'onepager' ), 'section' => 'op_contact', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_contact_email', array( 'default' => 'hello@example.com', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_contact_email', array( 'label' => __( 'Email', 'onepager' ), 'section' => 'op_contact', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_contact_hours', array( 'default' => "Monday – Friday: 08:00 – 18:00\nSaturday: By appointment\nSunday: Closed", 'sanitize_callback' => 'wp_kses_post' ) );
    $wp_customize->add_control( 'op_contact_hours', array( 'label' => __( 'Opening Hours', 'onepager' ), 'section' => 'op_contact', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_contact_form_heading', array( 'default' => 'Send Us a Message', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_contact_form_heading', array( 'label' => __( 'Form Heading', 'onepager' ), 'section' => 'op_contact', 'type' => 'text' ) );

    // =========================================================================
    // Section 9: CTA
    // =========================================================================
    $wp_customize->add_section( 'op_cta', array(
        'title' => __( 'Call to Action', 'onepager' ),
        'panel' => 'op_panel',
    ) );

    $wp_customize->add_setting( 'op_cta_title', array( 'default' => 'Ready to Get Started?', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_cta_title', array( 'label' => __( 'Title', 'onepager' ), 'section' => 'op_cta', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_cta_text', array( 'default' => 'Book an appointment today — no referral needed. We take the time to understand your needs and find the best solution.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_cta_text', array( 'label' => __( 'Text', 'onepager' ), 'section' => 'op_cta', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_cta_phone', array( 'default' => '234 567 890', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_cta_phone', array( 'label' => __( 'Phone Number', 'onepager' ), 'section' => 'op_cta', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_cta_btn_call', array( 'default' => 'Call Us', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_cta_btn_call', array( 'label' => __( 'Call Button Text', 'onepager' ), 'section' => 'op_cta', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_cta_btn_email', array( 'default' => 'Send Email', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_cta_btn_email', array( 'label' => __( 'Email Button Text', 'onepager' ), 'section' => 'op_cta', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_cta_trust_note', array( 'default' => 'Certified professionals — meeting the highest industry standards', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_cta_trust_note', array( 'label' => __( 'Trust Note', 'onepager' ), 'section' => 'op_cta', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_cta_trust_icon', array( 'default' => 'fa-shield-alt', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_cta_trust_icon', array( 'label' => __( 'Trust Note — Icon', 'onepager' ), 'section' => 'op_cta', 'type' => 'select', 'choices' => op_get_icon_choices() ) );

    // FAQ header (under CTA section in Customizer)
    $wp_customize->add_setting( 'op_faq_label', array( 'default' => 'Questions & Answers', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_faq_label', array( 'label' => __( 'FAQ — Section Label', 'onepager' ), 'section' => 'op_cta', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_faq_title', array( 'default' => 'Frequently Asked Questions', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_faq_title', array( 'label' => __( 'FAQ — Section Title', 'onepager' ), 'section' => 'op_cta', 'type' => 'text' ) );

    // =========================================================================
    // Section 10: Footer
    // =========================================================================
    $wp_customize->add_section( 'op_footer', array(
        'title' => __( 'Footer', 'onepager' ),
        'panel' => 'op_panel',
    ) );

    $wp_customize->add_setting( 'op_footer_tagline', array( 'default' => 'Professional services in the heart of your city. Trusted experts since 2020.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_footer_tagline', array( 'label' => __( 'Tagline', 'onepager' ), 'section' => 'op_footer', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_footer_copyright', array( 'default' => 'Your Company. All rights reserved.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_footer_copyright', array( 'label' => __( 'Copyright Text', 'onepager' ), 'section' => 'op_footer', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_footer_membership', array( 'default' => '', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_footer_membership', array( 'label' => __( 'Membership — Organization', 'onepager' ), 'section' => 'op_footer', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_footer_membership_url', array( 'default' => '', 'sanitize_callback' => 'esc_url_raw' ) );
    $wp_customize->add_control( 'op_footer_membership_url', array( 'label' => __( 'Membership — URL', 'onepager' ), 'section' => 'op_footer', 'type' => 'url' ) );

    // =========================================================================
    // Section 11: Enterprise (was Bedrift)
    // =========================================================================
    $wp_customize->add_section( 'op_enterprise', array(
        'title' => __( 'Enterprise', 'onepager' ),
        'panel' => 'op_panel',
    ) );

    $wp_customize->add_setting( 'op_enterprise_label', array( 'default' => 'Enterprise', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_enterprise_label', array( 'label' => __( 'Section Label', 'onepager' ), 'section' => 'op_enterprise', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_enterprise_title', array( 'default' => 'Services for Businesses', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_enterprise_title', array( 'label' => __( 'Section Title', 'onepager' ), 'section' => 'op_enterprise', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_enterprise_subtitle', array( 'default' => 'We work to improve the well-being and productivity of your team — through thorough assessment, tailored solutions, and preventive measures for each individual.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_enterprise_subtitle', array( 'label' => __( 'Subtitle', 'onepager' ), 'section' => 'op_enterprise', 'type' => 'textarea' ) );

    // Benefits 1-6
    $benefits = array(
        1 => array( 'Reduced Downtime', 'fa-calendar-check' ),
        2 => array( 'Improved Satisfaction', 'fa-smile' ),
        3 => array( 'Lower Costs', 'fa-piggy-bank' ),
        4 => array( 'Increased Productivity', 'fa-chart-line' ),
        5 => array( 'Better Work Environment', 'fa-users' ),
        6 => array( '', 'fa-check' ),
    );
    foreach ( $benefits as $i => $b ) {
        $wp_customize->add_setting( "op_enterprise_benefit{$i}_text", array( 'default' => $b[0], 'sanitize_callback' => 'sanitize_text_field' ) );
        $wp_customize->add_control( "op_enterprise_benefit{$i}_text", array( 'label' => sprintf( __( 'Benefit %d — Text', 'onepager' ), $i ), 'section' => 'op_enterprise', 'type' => 'text' ) );
        $wp_customize->add_setting( "op_enterprise_benefit{$i}_icon", array( 'default' => $b[1], 'sanitize_callback' => 'sanitize_text_field' ) );
        $wp_customize->add_control( "op_enterprise_benefit{$i}_icon", array( 'label' => sprintf( __( 'Benefit %d — Icon', 'onepager' ), $i ), 'section' => 'op_enterprise', 'type' => 'select', 'choices' => op_get_icon_choices() ) );
    }

    $wp_customize->add_setting( 'op_enterprise_description', array( 'default' => 'Through assessments, consultations, and thorough analysis of your organization, we develop cost-effective solutions. We can prevent staff from going on extended leave, protect healthy employees from overwork, and help those already on leave return to productive work.', 'sanitize_callback' => 'wp_kses_post' ) );
    $wp_customize->add_control( 'op_enterprise_description', array( 'label' => __( 'Main Text', 'onepager' ), 'section' => 'op_enterprise', 'type' => 'textarea' ) );

    // Service cards 1-3
    $cards = array(
        1 => array( 'fa-building', 'On-Site Services', 'We visit your office at regular intervals to provide services on location. We bring our own equipment and just need a room.' ),
        2 => array( 'fa-receipt', 'Flexible Billing', 'Your company covers part or all of the cost. We send invoices monthly or as agreed.' ),
        3 => array( 'fa-percentage', 'Tax Benefits', 'Preventive services at the workplace may qualify for tax deductions. Employees are not burdened with benefit taxation.' ),
    );
    foreach ( $cards as $i => $c ) {
        $wp_customize->add_setting( "op_enterprise_card{$i}_icon", array( 'default' => $c[0], 'sanitize_callback' => 'sanitize_text_field' ) );
        $wp_customize->add_control( "op_enterprise_card{$i}_icon", array( 'label' => sprintf( __( 'Service %d — Icon', 'onepager' ), $i ), 'section' => 'op_enterprise', 'type' => 'select', 'choices' => op_get_icon_choices() ) );
        $wp_customize->add_setting( "op_enterprise_card{$i}_title", array( 'default' => $c[1], 'sanitize_callback' => 'sanitize_text_field' ) );
        $wp_customize->add_control( "op_enterprise_card{$i}_title", array( 'label' => sprintf( __( 'Service %d — Title', 'onepager' ), $i ), 'section' => 'op_enterprise', 'type' => 'text' ) );
        $wp_customize->add_setting( "op_enterprise_card{$i}_text", array( 'default' => $c[2], 'sanitize_callback' => 'sanitize_text_field' ) );
        $wp_customize->add_control( "op_enterprise_card{$i}_text", array( 'label' => sprintf( __( 'Service %d — Text', 'onepager' ), $i ), 'section' => 'op_enterprise', 'type' => 'textarea' ) );
    }

    // Statistics
    $wp_customize->add_setting( 'op_enterprise_stat_icon', array( 'default' => 'fa-exclamation-triangle', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_enterprise_stat_icon', array( 'label' => __( 'Stats — Icon', 'onepager' ), 'section' => 'op_enterprise', 'type' => 'select', 'choices' => op_get_icon_choices() ) );
    $wp_customize->add_setting( 'op_enterprise_stat_heading', array( 'default' => 'The Cost of Downtime', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_enterprise_stat_heading', array( 'label' => __( 'Stats — Heading', 'onepager' ), 'section' => 'op_enterprise', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_enterprise_stat1', array( 'default' => 'Employee absence is the most common cause of reduced productivity.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_enterprise_stat1', array( 'label' => __( 'Stat 1', 'onepager' ), 'section' => 'op_enterprise', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_enterprise_stat2', array( 'default' => 'Studies show companies lose an average of $1,000 per week for each absent employee, not counting salary costs.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_enterprise_stat2', array( 'label' => __( 'Stat 2', 'onepager' ), 'section' => 'op_enterprise', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_enterprise_stat3', array( 'default' => 'Industry data shows millions of lost workdays annually due to preventable issues.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_enterprise_stat3', array( 'label' => __( 'Stat 3', 'onepager' ), 'section' => 'op_enterprise', 'type' => 'textarea' ) );

    $wp_customize->add_setting( 'op_enterprise_cta_text', array( 'default' => 'Contact us for a tailored enterprise quote. We are happy to visit your office for a presentation of our services.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_enterprise_cta_text', array( 'label' => __( 'CTA Text', 'onepager' ), 'section' => 'op_enterprise', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_enterprise_cta_button', array( 'default' => 'Request a Quote', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_enterprise_cta_button', array( 'label' => __( 'CTA Button Text', 'onepager' ), 'section' => 'op_enterprise', 'type' => 'text' ) );

    // =========================================================================
    // Section 12: Thank You
    // =========================================================================
    $wp_customize->add_section( 'op_thankyou', array(
        'title' => __( 'Thank You Page', 'onepager' ),
        'panel' => 'op_panel',
    ) );

    $wp_customize->add_setting( 'op_thankyou_heading', array( 'default' => 'Thank You for Your Inquiry!', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_thankyou_heading', array( 'label' => __( 'Heading', 'onepager' ), 'section' => 'op_thankyou', 'type' => 'text' ) );
    $wp_customize->add_setting( 'op_thankyou_text', array( 'default' => 'We have received your message and will respond as soon as possible — usually within one business day.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_thankyou_text', array( 'label' => __( 'Text', 'onepager' ), 'section' => 'op_thankyou', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'op_thankyou_button', array( 'default' => 'Back to Home', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'op_thankyou_button', array( 'label' => __( 'Button Text', 'onepager' ), 'section' => 'op_thankyou', 'type' => 'text' ) );
}
add_action( 'customize_register', 'op_customize_register' );
