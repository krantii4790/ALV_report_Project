REPORT y182_emp_salary_alv.

*---------------------------------------------------------------------*
* Employee Salary Management - ALV Report (Enhanced)
* Tables : Y182M_EMPMST (Employee Master), Y182M_SALMST (Salary Master)
*
* ALV features used:
*   1.  Field catalog with DDIC reference, key columns, hotspot,
*       hidden (no_out) column, column alignment
*   2.  Layout: zebra, optimized width, row selection checkbox,
*       traffic lights, row colouring, totals/subtotals texts,
*       window title, exit confirmation
*   3.  Sorting with department-wise subtotals + grand totals
*   4.  Currency-aware totals (split per currency automatically)
*   5.  Layout variants (F4 help, default variant, save)
*   6.  Top-of-page header and end-of-list footer
*   7.  Hotspot / double-click -> popup ALV with employee details
*   8.  Custom user commands (selected-row summary, refresh)
*   9.  GUI status handling (standard / optional custom status)
*   10. Print settings
*   11. Built-in: filter, sort, find, export to Excel, print,
*       detail view, change layout (all from standard toolbar)
*---------------------------------------------------------------------*

TABLES: y182m_empmst,
        y182m_salmst.

TYPE-POOLS: slis.

*---------------------------------------------------------------------*
* Types and Data
*---------------------------------------------------------------------*
TYPES: BEGIN OF ty_report,
         empno       TYPE y182m_empmst-empno,
         empnm       TYPE y182m_empmst-empnm,
         gender      TYPE y182m_empmst-gender,
         deptcd      TYPE y182m_empmst-deptcd,
         designation TYPE y182m_empmst-designation,
         phone_no    TYPE y182m_empmst-phone_no,
         salhd       TYPE y182m_salmst-salhd,
         salary      TYPE y182m_salmst-salary,
         waers       TYPE y182m_salmst-waers,
       END OF ty_report.

* Output structure = report fields + ALV helper columns
TYPES: BEGIN OF ty_out.
         INCLUDE TYPE ty_report.
TYPES:   light    TYPE c LENGTH 1,   " traffic light (1/2/3)
         box      TYPE c LENGTH 1,   " row selection checkbox
         rowcolor TYPE c LENGTH 4,   " row colour code (Cnnn)
       END OF ty_out.

TYPES: BEGIN OF ty_total,
         waers TYPE y182m_salmst-waers,
         total TYPE y182m_salmst-salary,
       END OF ty_total.

DATA: gt_out      TYPE STANDARD TABLE OF ty_out,
      gs_out      TYPE ty_out,
      gt_fieldcat TYPE slis_t_fieldcat_alv,
      gs_fieldcat TYPE slis_fieldcat_alv,
      gt_sort     TYPE slis_t_sortinfo_alv,
      gs_sort     TYPE slis_sortinfo_alv,
      gs_layout   TYPE slis_layout_alv,
      gt_events   TYPE slis_t_event,
      gs_print    TYPE slis_print_alv,
      gs_variant  TYPE disvariant,
      gs_variant_x TYPE disvariant,
      gv_emp_cnt  TYPE i.

* Set to abap_true after creating GUI status ZSALARY_ALV in SE41
* (copy of SAPLKKBL / STANDARD_FULLSCREEN + buttons ZSELECT, ZREFRESH)
CONSTANTS gc_custom_status TYPE abap_bool VALUE abap_false.

*---------------------------------------------------------------------*
* Selection Screen
*---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE t_b1.
SELECT-OPTIONS: s_empno FOR y182m_empmst-empno,
                s_dept  FOR y182m_empmst-deptcd,
                s_desig FOR y182m_empmst-designation,
                s_sal   FOR y182m_salmst-salary.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE t_b2.
PARAMETERS: p_thr   TYPE y182m_salmst-salary DEFAULT 50000,
            p_light AS CHECKBOX DEFAULT 'X',
            p_color AS CHECKBOX DEFAULT 'X',
            p_sub   AS CHECKBOX DEFAULT 'X',
            p_phone AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE t_b3.
PARAMETERS p_vari TYPE slis_vari.
SELECTION-SCREEN END OF BLOCK b3.

*---------------------------------------------------------------------*
INITIALIZATION.
*---------------------------------------------------------------------*
  t_b1 = 'Selection Criteria'.
  t_b2 = 'Display Options'.
  t_b3 = 'ALV Layout'.

  %_s_empno_%_app_%-text = 'Employee Number'.
  %_s_dept_%_app_%-text  = 'Department'.
  %_s_desig_%_app_%-text = 'Designation'.
  %_s_sal_%_app_%-text   = 'Salary Amount'.
  %_p_thr_%_app_%-text   = 'High Salary Limit'.
  %_p_light_%_app_%-text = 'Show Salary Status Lights'.
  %_p_color_%_app_%-text = 'Highlight High Earners'.
  %_p_sub_%_app_%-text   = 'Department-wise Subtotals'.
  %_p_phone_%_app_%-text = 'Show Phone Number Column'.
  %_p_vari_%_app_%-text  = 'Layout Variant'.

* Default layout variant
  gs_variant-report = sy-repid.
  CALL FUNCTION 'REUSE_ALV_VARIANT_DEFAULT_GET'
    EXPORTING
      i_save     = 'A'
    CHANGING
      cs_variant = gs_variant
    EXCEPTIONS
      not_found  = 2
      OTHERS     = 1.
  IF sy-subrc = 0.
    p_vari = gs_variant-variant.
  ENDIF.

*---------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_vari.
*---------------------------------------------------------------------*
  gs_variant_x-report = sy-repid.
  CALL FUNCTION 'REUSE_ALV_VARIANT_F4'
    EXPORTING
      is_variant = gs_variant_x
      i_save     = 'A'
    IMPORTING
      es_variant = gs_variant_x
    EXCEPTIONS
      not_found  = 2
      OTHERS     = 1.
  IF sy-subrc = 0.
    p_vari = gs_variant_x-variant.
  ENDIF.

*---------------------------------------------------------------------*
AT SELECTION-SCREEN.
*---------------------------------------------------------------------*
  IF p_thr <= 0.
    MESSAGE 'High salary limit must be greater than zero' TYPE 'E'.
  ENDIF.

  IF p_vari IS NOT INITIAL.
    gs_variant_x-report  = sy-repid.
    gs_variant_x-variant = p_vari.
    CALL FUNCTION 'REUSE_ALV_VARIANT_EXISTENCE'
      EXPORTING
        i_save     = 'A'
      CHANGING
        cs_variant = gs_variant_x
      EXCEPTIONS
        wrong_input   = 1
        not_found     = 2
        program_error = 3
        OTHERS        = 4.
    IF sy-subrc <> 0.
      MESSAGE 'Selected layout variant does not exist' TYPE 'E'.
    ENDIF.
  ENDIF.

*---------------------------------------------------------------------*
START-OF-SELECTION.
*---------------------------------------------------------------------*
  PERFORM get_data.

  IF gt_out IS INITIAL.
    MESSAGE 'No employee salary records found' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  PERFORM build_fieldcat.
  PERFORM build_sort.
  PERFORM build_layout.
  PERFORM build_events.
  PERFORM display_alv.

*---------------------------------------------------------------------*
* Read data and set traffic light / row colour
*---------------------------------------------------------------------*
FORM get_data.

  FIELD-SYMBOLS <ls_out> TYPE ty_out.

  CLEAR: gt_out, gv_emp_cnt.

  SELECT e~empno,
         e~empnm,
         e~gender,
         e~deptcd,
         e~designation,
         e~phone_no,
         s~salhd,
         s~salary,
         s~waers
    FROM y182m_empmst AS e
    INNER JOIN y182m_salmst AS s
      ON e~empno = s~empno
    WHERE e~empno       IN @s_empno
      AND e~deptcd      IN @s_dept
      AND e~designation IN @s_desig
      AND s~salary      IN @s_sal
    INTO CORRESPONDING FIELDS OF TABLE @gt_out.

  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  LOOP AT gt_out ASSIGNING <ls_out>.

*   Salary status: 3 = green, 2 = yellow, 1 = red
    IF <ls_out>-salary >= p_thr.
      <ls_out>-light = '3'.
      IF p_color = abap_true.
        <ls_out>-rowcolor = 'C510'.      " green row
      ENDIF.
    ELSEIF <ls_out>-salary >= p_thr / 2.
      <ls_out>-light = '2'.
    ELSE.
      <ls_out>-light = '1'.
    ENDIF.

  ENDLOOP.

* Number of distinct employees
  DATA(lt_emp) = gt_out.
  SORT lt_emp BY empno.
  DELETE ADJACENT DUPLICATES FROM lt_emp COMPARING empno.
  gv_emp_cnt = lines( lt_emp ).

ENDFORM.

*---------------------------------------------------------------------*
* Field catalog
*---------------------------------------------------------------------*
FORM build_fieldcat.

  FIELD-SYMBOLS <fc> TYPE slis_fieldcat_alv.

  CLEAR gt_fieldcat.

  PERFORM add_field USING 'EMPNO'       'Employee Number' 12 'Y182M_EMPMST'.
  PERFORM add_field USING 'EMPNM'       'Employee Name'   25 'Y182M_EMPMST'.
  PERFORM add_field USING 'GENDER'      'Gender'          10 'Y182M_EMPMST'.
  PERFORM add_field USING 'DEPTCD'      'Department'      12 'Y182M_EMPMST'.
  PERFORM add_field USING 'DESIGNATION' 'Designation'     20 'Y182M_EMPMST'.
  PERFORM add_field USING 'PHONE_NO'    'Phone Number'    15 'Y182M_EMPMST'.
  PERFORM add_field USING 'SALHD'       'Salary Head'     12 'Y182M_SALMST'.
  PERFORM add_field USING 'SALARY'      'Salary Amount'   18 'Y182M_SALMST'.
  PERFORM add_field USING 'WAERS'       'Currency'         8 'Y182M_SALMST'.

* Column specific properties
  LOOP AT gt_fieldcat ASSIGNING <fc>.
    CASE <fc>-fieldname.

      WHEN 'EMPNO'.
        <fc>-hotspot    = 'X'.       " clickable -> popup
        <fc>-key        = 'X'.       " key column (fixed, coloured)
        <fc>-fix_column = 'X'.

      WHEN 'EMPNM'.
        <fc>-key        = 'X'.
        <fc>-fix_column = 'X'.

      WHEN 'GENDER' OR 'WAERS'.
        <fc>-just       = 'C'.       " centered

      WHEN 'PHONE_NO'.
        IF p_phone = abap_false.
          <fc>-no_out   = 'X'.       " hidden, user can add via layout
        ENDIF.

      WHEN 'SALARY'.
        <fc>-do_sum     = 'X'.       " totals / subtotals
        <fc>-cfieldname = 'WAERS'.   " currency reference
        <fc>-no_zero    = 'X'.

    ENDCASE.
  ENDLOOP.

ENDFORM.

FORM add_field USING pv_field  TYPE csequence
                     pv_text   TYPE csequence
                     pv_width  TYPE i
                     pv_reftab TYPE csequence.

  CLEAR gs_fieldcat.

  gs_fieldcat-fieldname     = pv_field.
  gs_fieldcat-seltext_s     = pv_text.
  gs_fieldcat-seltext_m     = pv_text.
  gs_fieldcat-seltext_l     = pv_text.
  gs_fieldcat-reptext_ddic  = pv_text.
  gs_fieldcat-outputlen     = pv_width.
  gs_fieldcat-ref_tabname   = pv_reftab.   " F1 help / DDIC info
  gs_fieldcat-ref_fieldname = pv_field.

  APPEND gs_fieldcat TO gt_fieldcat.

ENDFORM.

*---------------------------------------------------------------------*
* Sort and subtotal
*---------------------------------------------------------------------*
FORM build_sort.

  CLEAR gt_sort.

  CLEAR gs_sort.
  gs_sort-spos      = 1.
  gs_sort-fieldname = 'DEPTCD'.
  gs_sort-up        = 'X'.
  IF p_sub = abap_true.
    gs_sort-subtot  = 'X'.           " subtotal on every department
  ENDIF.
  APPEND gs_sort TO gt_sort.

  CLEAR gs_sort.
  gs_sort-spos      = 2.
  gs_sort-fieldname = 'EMPNO'.
  gs_sort-up        = 'X'.
  APPEND gs_sort TO gt_sort.

  CLEAR gs_sort.
  gs_sort-spos      = 3.
  gs_sort-fieldname = 'SALHD'.
  gs_sort-up        = 'X'.
  APPEND gs_sort TO gt_sort.

ENDFORM.

*---------------------------------------------------------------------*
* Layout, print settings, variant
*---------------------------------------------------------------------*
FORM build_layout.

  CLEAR gs_layout.

  gs_layout-zebra               = 'X'.
  gs_layout-colwidth_optimize   = 'X'.
  gs_layout-box_fieldname       = 'BOX'.        " selection checkbox
  gs_layout-totals_text         = 'Grand Total'.
  gs_layout-subtotals_text      = 'Dept Total'.
  gs_layout-window_titlebar     = 'Employee Salary Management'.
  gs_layout-confirmation_prompt = 'X'.          " ask before exit
  gs_layout-detail_popup        = 'X'.          " detail view popup

  IF p_light = abap_true.
    gs_layout-lights_fieldname  = 'LIGHT'.
  ENDIF.

  IF p_color = abap_true.
    gs_layout-info_fieldname    = 'ROWCOLOR'.
  ENDIF.

  gs_print-no_print_selinfos    = 'X'.
  gs_print-no_coverpage         = 'X'.

  gs_variant-report  = sy-repid.
  gs_variant-variant = p_vari.

ENDFORM.

*---------------------------------------------------------------------*
* Events (top of page / end of list)
*---------------------------------------------------------------------*
FORM build_events.

  FIELD-SYMBOLS <ev> TYPE slis_alv_event.

  CALL FUNCTION 'REUSE_ALV_EVENTS_GET'
    EXPORTING
      i_list_type = 0
    IMPORTING
      et_events   = gt_events.

  READ TABLE gt_events ASSIGNING <ev>
       WITH KEY name = slis_ev_top_of_page.
  IF sy-subrc = 0.
    <ev>-form = 'TOP_OF_PAGE'.
  ENDIF.

  READ TABLE gt_events ASSIGNING <ev>
       WITH KEY name = slis_ev_end_of_list.
  IF sy-subrc = 0.
    <ev>-form = 'END_OF_LIST'.
  ENDIF.

ENDFORM.

*---------------------------------------------------------------------*
* Display ALV grid
*---------------------------------------------------------------------*
FORM display_alv.

  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING
      i_callback_program       = sy-repid
      i_callback_pf_status_set = 'SET_PF_STATUS'
      i_callback_user_command  = 'USER_COMMAND'
      i_grid_title             = 'Employee Salary Details'
      is_layout                = gs_layout
      it_fieldcat              = gt_fieldcat
      it_sort                  = gt_sort
      it_events                = gt_events
      is_print                 = gs_print
      is_variant               = gs_variant
      i_default                = 'X'
      i_save                   = 'A'
    TABLES
      t_outtab                 = gt_out
    EXCEPTIONS
      program_error            = 1
      OTHERS                   = 2.

  IF sy-subrc <> 0.
    MESSAGE 'Error displaying ALV report' TYPE 'E'.
  ENDIF.

ENDFORM.

*---------------------------------------------------------------------*
* GUI status
*---------------------------------------------------------------------*
FORM set_pf_status USING pt_extab TYPE slis_t_extab.

  IF gc_custom_status = abap_true.
    SET PF-STATUS 'ZSALARY_ALV' EXCLUDING pt_extab.
  ELSE.
    SET PF-STATUS 'STANDARD_FULLSCREEN' OF PROGRAM 'SAPLKKBL'
        EXCLUDING pt_extab.
  ENDIF.

ENDFORM.

*---------------------------------------------------------------------*
* User commands (hotspot, double-click, custom buttons)
*---------------------------------------------------------------------*
FORM user_command USING pv_ucomm    LIKE sy-ucomm
                        ps_selfield TYPE slis_selfield.

  CASE pv_ucomm.

*   Hotspot / double-click on a data row
    WHEN '&IC1'.
      IF ps_selfield-tabindex > 0.
        READ TABLE gt_out INTO gs_out INDEX ps_selfield-tabindex.
        IF sy-subrc = 0.
          PERFORM show_employee_popup USING gs_out-empno.
        ENDIF.
      ELSE.
        MESSAGE 'Please click on an employee row' TYPE 'S'.
      ENDIF.

*   Custom button: summary of selected rows
    WHEN 'ZSELECT'.
      PERFORM show_selected.

*   Custom button: reload data from database
    WHEN 'ZREFRESH'.
      PERFORM get_data.
      ps_selfield-refresh    = 'X'.
      ps_selfield-row_stable = 'X'.
      ps_selfield-col_stable = 'X'.
      MESSAGE 'Data refreshed' TYPE 'S'.

  ENDCASE.

ENDFORM.

*---------------------------------------------------------------------*
* Popup ALV: all salary records of one employee
*---------------------------------------------------------------------*
FORM show_employee_popup USING pv_empno TYPE y182m_empmst-empno.

  DATA: lt_popup TYPE STANDARD TABLE OF ty_out,
        lt_fc    TYPE slis_t_fieldcat_alv,
        lv_title TYPE c LENGTH 60,
        lv_name  TYPE y182m_empmst-empnm.

  LOOP AT gt_out INTO DATA(ls_row) WHERE empno = pv_empno.
    lv_name = ls_row-empnm.
    APPEND ls_row TO lt_popup.
  ENDLOOP.

  IF lt_popup IS INITIAL.
    RETURN.
  ENDIF.

  PERFORM add_popup_col USING 'DEPTCD'      'Department'    10 CHANGING lt_fc.
  PERFORM add_popup_col USING 'DESIGNATION' 'Designation'   20 CHANGING lt_fc.
  PERFORM add_popup_col USING 'PHONE_NO'    'Phone Number'  15 CHANGING lt_fc.
  PERFORM add_popup_col USING 'SALHD'       'Salary Head'   12 CHANGING lt_fc.
  PERFORM add_popup_col USING 'SALARY'      'Salary Amount' 18 CHANGING lt_fc.
  PERFORM add_popup_col USING 'WAERS'       'Currency'       8 CHANGING lt_fc.

  lv_title = |{ lv_name } ({ pv_empno })|.

  CALL FUNCTION 'REUSE_ALV_POPUP_TO_SELECT'
    EXPORTING
      i_title               = lv_title
      i_selection           = space
      i_zebra               = 'X'
      i_screen_start_column = 10
      i_screen_start_line   = 5
      i_screen_end_column   = 105
      i_screen_end_line     = 15
      i_tabname             = 'GT_POPUP'
      it_fieldcat           = lt_fc
    TABLES
      t_outtab              = lt_popup
    EXCEPTIONS
      program_error         = 1
      OTHERS                = 2.

  IF sy-subrc <> 0.
    MESSAGE 'Unable to display employee details' TYPE 'S' DISPLAY LIKE 'E'.
  ENDIF.

ENDFORM.

FORM add_popup_col USING    pv_field TYPE csequence
                            pv_text  TYPE csequence
                            pv_width TYPE i
                   CHANGING pt_fc    TYPE slis_t_fieldcat_alv.

  DATA ls_fc TYPE slis_fieldcat_alv.

  ls_fc-fieldname = pv_field.
  ls_fc-tabname   = 'GT_POPUP'.
  ls_fc-seltext_l = pv_text.
  ls_fc-seltext_m = pv_text.
  ls_fc-seltext_s = pv_text.
  ls_fc-outputlen = pv_width.

  IF pv_field = 'SALARY'.
    ls_fc-cfieldname = 'WAERS'.
    ls_fc-ctabname   = 'GT_POPUP'.
  ENDIF.

  APPEND ls_fc TO pt_fc.

ENDFORM.

*---------------------------------------------------------------------*
* Summary of rows ticked in the checkbox column
*---------------------------------------------------------------------*
FORM show_selected.

  DATA: lt_tot  TYPE STANDARD TABLE OF ty_total,
        ls_tot  TYPE ty_total,
        lv_cnt  TYPE i,
        lv_text TYPE string.

  LOOP AT gt_out INTO DATA(ls_row) WHERE box = 'X'.
    lv_cnt = lv_cnt + 1.
    CLEAR ls_tot.
    ls_tot-waers = ls_row-waers.
    ls_tot-total = ls_row-salary.
    COLLECT ls_tot INTO lt_tot.
  ENDLOOP.

  IF lv_cnt = 0.
    MESSAGE 'Please select at least one row' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  lv_text = |{ lv_cnt } row(s) selected. Total:|.
  LOOP AT lt_tot INTO ls_tot.
    lv_text = |{ lv_text } { ls_tot-total CURRENCY = ls_tot-waers } { ls_tot-waers }|.
  ENDLOOP.

  MESSAGE lv_text TYPE 'I'.

ENDFORM.

*---------------------------------------------------------------------*
* Top of page
*---------------------------------------------------------------------*
FORM top_of_page.

  DATA: lt_head TYPE slis_t_listheader,
        ls_head TYPE slis_listheader.

  ls_head-typ  = 'H'.
  ls_head-info = 'Employee Salary Management Report'.
  APPEND ls_head TO lt_head.

  CLEAR ls_head.
  ls_head-typ  = 'S'.
  ls_head-key  = 'Run By'.
  ls_head-info = sy-uname.
  APPEND ls_head TO lt_head.

  ls_head-key  = 'Date'.
  ls_head-info = |{ sy-datum DATE = USER }|.
  APPEND ls_head TO lt_head.

  ls_head-key  = 'Time'.
  ls_head-info = |{ sy-uzeit TIME = USER }|.
  APPEND ls_head TO lt_head.

  ls_head-key  = 'Employees'.
  ls_head-info = |{ gv_emp_cnt }|.
  APPEND ls_head TO lt_head.

  ls_head-key  = 'Salary Records'.
  ls_head-info = |{ lines( gt_out ) }|.
  APPEND ls_head TO lt_head.

  ls_head-key  = 'High Salary Limit'.
  ls_head-info = |{ p_thr }|.
  APPEND ls_head TO lt_head.

  CLEAR ls_head.
  ls_head-typ  = 'A'.
  ls_head-info = 'Status: Green = at/above limit, Yellow = at/above 50%, Red = below 50%'.
  APPEND ls_head TO lt_head.

  CALL FUNCTION 'REUSE_ALV_COMMENTARY_WRITE'
    EXPORTING
      it_list_commentary = lt_head.

ENDFORM.

*---------------------------------------------------------------------*
* End of list
*---------------------------------------------------------------------*
FORM end_of_list.

  DATA: lt_head TYPE slis_t_listheader,
        ls_head TYPE slis_listheader.

  ls_head-typ  = 'S'.
  ls_head-key  = 'Total Records'.
  ls_head-info = |{ lines( gt_out ) }|.
  APPEND ls_head TO lt_head.

  CLEAR ls_head.
  ls_head-typ  = 'A'.
  ls_head-info = '*** End of Report ***'.
  APPEND ls_head TO lt_head.

  CALL FUNCTION 'REUSE_ALV_COMMENTARY_WRITE'
    EXPORTING
      it_list_commentary = lt_head
      i_end_of_list_grid = 'X'.

ENDFORM.
