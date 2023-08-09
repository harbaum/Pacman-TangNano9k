// usb_host.c

#include "usbh_core.h"
#include "usbh_hid.h"
#include "bflb_gpio.h"

extern struct bflb_device_s *gpio;

USB_NOCACHE_RAM_SECTION USB_MEM_ALIGNX uint8_t hid_buffer[128];

struct usbh_urb hid_intin_urb;

void usbh_hid_callback(void *arg, int nbytes) {
  if (nbytes > 0) {
    for (size_t i = 0; i < nbytes; i++) {
      USB_LOG_RAW("0x%02x ", hid_buffer[i]);
    }
    USB_LOG_RAW("nbytes:%d\r\n", nbytes);
    usbh_submit_urb(&hid_intin_urb);
  }
  
  if (nbytes >= 3) {
    // drive led from button[0]
    if(hid_buffer[2] & 1) bflb_gpio_reset(gpio, GPIO_PIN_28);
    else                  bflb_gpio_set(gpio, GPIO_PIN_28);
    
    // drive digital direction outputs
    
    // joystick up/down
    if(hid_buffer[1] < 64) {
      bflb_gpio_reset(gpio, GPIO_PIN_10);  // up
      bflb_gpio_set(gpio, GPIO_PIN_11);    // not down
    } else if(hid_buffer[1] > 192) {
      bflb_gpio_set(gpio, GPIO_PIN_10);    // not up
      bflb_gpio_reset(gpio, GPIO_PIN_11);  // down
    } else {
      bflb_gpio_set(gpio, GPIO_PIN_10);    // neither up
      bflb_gpio_set(gpio, GPIO_PIN_11);    // now down
    }

    // joystick left/right
    if(hid_buffer[0] < 64) {
      bflb_gpio_reset(gpio, GPIO_PIN_12);  // left
      bflb_gpio_set(gpio, GPIO_PIN_13);    // not right
    } else if(hid_buffer[0] > 192) {
      bflb_gpio_set(gpio, GPIO_PIN_12);    // not right
      bflb_gpio_reset(gpio, GPIO_PIN_13);  // left
    } else {
      bflb_gpio_set(gpio, GPIO_PIN_12);    // neither right
      bflb_gpio_set(gpio, GPIO_PIN_13);    // now left
    }

    // fire buttons 0-3
    if(hid_buffer[2] & 1) bflb_gpio_reset(gpio, GPIO_PIN_14);
    else                  bflb_gpio_set(gpio, GPIO_PIN_14);
    if(hid_buffer[2] & 2) bflb_gpio_reset(gpio, GPIO_PIN_15);
    else                  bflb_gpio_set(gpio, GPIO_PIN_15);
    if(hid_buffer[2] & 4) bflb_gpio_reset(gpio, GPIO_PIN_16);
    else                  bflb_gpio_set(gpio, GPIO_PIN_16);
    if(hid_buffer[2] & 8) bflb_gpio_reset(gpio, GPIO_PIN_17);
    else                  bflb_gpio_set(gpio, GPIO_PIN_17);    
  }  
}

static void usbh_hid_thread(void *argument)
{
    int ret;
    struct usbh_hid *hid_class;

    while (1) {
        // clang-format off
find_class:
        // clang-format on
        hid_class = (struct usbh_hid *)usbh_find_class_instance("/dev/input0");
        if (hid_class == NULL) {
            USB_LOG_RAW("do not find /dev/input0\r\n");
            usb_osal_msleep(1500);
            continue;
        }
        usbh_int_urb_fill(&hid_intin_urb, hid_class->intin, hid_buffer, 8, 0, usbh_hid_callback, hid_class);
        ret = usbh_submit_urb(&hid_intin_urb);
        if (ret < 0) {
            usb_osal_msleep(1500);
            goto find_class;
        }

        while (1) {
            hid_class = (struct usbh_hid *)usbh_find_class_instance("/dev/input0");
            if (hid_class == NULL) {
                goto find_class;
            }
            usb_osal_msleep(1500);
        }
    }
}

void usbh_hid_run(struct usbh_hid *hid_class)
{
  // LED 1 on
  bflb_gpio_reset(gpio, GPIO_PIN_27);
}

void usbh_hid_stop(struct usbh_hid *hid_class)
{
  // LED 1 off
  bflb_gpio_set(gpio, GPIO_PIN_27);
}

void usbh_class_test(void)
{
    usb_osal_thread_create("usbh_hid", 2048, CONFIG_USBHOST_PSC_PRIO + 1, usbh_hid_thread, NULL);
}
